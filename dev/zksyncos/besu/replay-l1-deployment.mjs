// Replays the recorded L1 deployment txs onto Besu, regenerating the contracts + event logs.
// Pure Node built-ins: RLP re-serialization of the already-signed txs + fetch.
// Usage: node replay-l1-deployment.mjs <l1-state.json.gz> <rpc-url>

import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

const [, , statePath, rpcUrl] = process.argv;
if (!statePath || !rpcUrl) {
    console.error('usage: replay-l1-deployment.mjs <l1-state.json.gz> <rpc-url>');
    process.exit(1);
}

const concat = (arrays) => Buffer.concat(arrays);

function encodeLength(len, offset) {
    if (len < 56) return Buffer.from([offset + len]);
    let hex = len.toString(16);
    if (hex.length % 2) hex = `0${hex}`;
    const lenBytes = Buffer.from(hex, 'hex');
    return concat([Buffer.from([offset + 55 + lenBytes.length]), lenBytes]);
}

function rlp(item) {
    if (Array.isArray(item)) {
        const body = concat(item.map(rlp));
        return concat([encodeLength(body.length, 0xc0), body]);
    }
    const b = item; // Buffer
    if (b.length === 1 && b[0] < 0x80) return b;
    return concat([encodeLength(b.length, 0x80), b]);
}

function scalar(hexQuantity) {
    let h = (hexQuantity ?? '0x0').replace(/^0x/, '').replace(/^0+/, '');
    if (h.length % 2) h = `0${h}`;
    return Buffer.from(h, 'hex');
}
function bytes(hex) {
    if (!hex || hex === '0x') return Buffer.alloc(0);
    const h = hex.replace(/^0x/, '');
    return Buffer.from(h.length % 2 ? `0${h}` : h, 'hex');
}
function accessListRlp(list) {
    return (list || []).map((e) => [bytes(e.address), (e.storageKeys || []).map(bytes)]);
}

function serialize(tx) {
    const kind = Object.keys(tx)[0];
    const f = tx[kind];
    if (kind === 'Legacy') {
        // dump stores parity; rebuild EIP-155 v
        const parity = BigInt(f.yParity ?? f.v);
        const v = f.chainId ? BigInt(f.chainId) * 2n + 35n + parity : 27n + parity;
        return `0x${rlp([
            scalar(f.nonce),
            scalar(f.gasPrice),
            scalar(f.gas),
            bytes(f.to),
            scalar(f.value),
            bytes(f.input),
            scalar(`0x${v.toString(16)}`),
            scalar(f.r),
            scalar(f.s)
        ]).toString('hex')}`;
    }
    if (kind === 'EIP1559') {
        const body = rlp([
            scalar(f.chainId),
            scalar(f.nonce),
            scalar(f.maxPriorityFeePerGas),
            scalar(f.maxFeePerGas),
            scalar(f.gas),
            bytes(f.to),
            scalar(f.value),
            bytes(f.input),
            accessListRlp(f.accessList),
            scalar(f.yParity ?? f.v),
            scalar(f.r),
            scalar(f.s)
        ]);
        return `0x02${body.toString('hex')}`;
    }
    throw new Error(`unsupported tx kind: ${kind}`);
}

let rpcId = 0;
async function call(method, params) {
    const res = await fetch(rpcUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params })
    });
    const json = await res.json();
    if (json.error) throw new Error(`${method}: ${JSON.stringify(json.error)}`);
    return json.result;
}

async function waitReceipt(hash, tries = 60) {
    for (let i = 0; i < tries; i++) {
        const r = await call('eth_getTransactionReceipt', [hash]);
        if (r) return r;
        await new Promise((res) => setTimeout(res, 500));
    }
    throw new Error(`timeout waiting for receipt ${hash}`);
}

async function waitForRpc(tries = 60) {
    for (let i = 0; i < tries; i++) {
        try {
            await call('eth_chainId', []);
            return;
        } catch {
            await new Promise((res) => setTimeout(res, 1000));
        }
    }
    throw new Error(`timeout waiting for RPC at ${rpcUrl}`);
}

async function main() {
    await waitForRpc();
    const dump = JSON.parse(gunzipSync(readFileSync(statePath)).toString('utf8'));

    const blocks = [...dump.blocks].sort((a, b) => parseInt(a.header.number, 16) - parseInt(b.header.number, 16));
    const ordered = [];
    for (const b of blocks) for (const tx of b.transactions || []) ordered.push(tx.transaction);
    console.log(`Replaying ${ordered.length} recorded L1 txs to ${rpcUrl}`);

    for (let i = 0; i < ordered.length; i++) {
        const raw = serialize(ordered[i]);
        const hash = await call('eth_sendRawTransaction', [raw]);
        const receipt = await waitReceipt(hash);
        if (receipt.status !== '0x1') throw new Error(`tx ${i} (${hash}) reverted: status=${receipt.status}`);
        if ((i + 1) % 20 === 0 || i === ordered.length - 1) console.log(`  ${i + 1}/${ordered.length} confirmed`);
    }
    console.log('L1 deployment replay complete');
}

main().catch((err) => {
    console.error('L1 replay failed:', err.message);
    process.exit(1);
});
