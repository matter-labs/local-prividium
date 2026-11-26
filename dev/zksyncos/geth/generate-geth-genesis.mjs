// Builds the Geth dev-mode genesis from the anvil L1 dump.
// Usage: node generate-geth-genesis.mjs <l1-state.json.gz> <geth-dev-genesis.json> <out-genesis.json>

import { readFileSync, writeFileSync } from 'node:fs';
import { readGenesisAlloc } from '../l1-genesis-alloc.mjs';

const [, , statePath, templatePath, outPath] = process.argv;
if (!statePath || !templatePath || !outPath) {
    console.error('usage: generate-geth-genesis.mjs <l1-state.json.gz> <geth-dev-genesis.json> <out-genesis.json>');
    process.exit(1);
}

const CHAIN_ID = 31337;
// Geth only accepts the Osaka (EIP-7594) blob sidecar, and the sequencer picks its sidecar format from the fork.
const POST_OSAKA_FORKS = ['bogota', 'amsterdam'];
const OSAKA_BLOBS = { target: 6, max: 9, baseFeeUpdateFraction: 5007716 };

// `geth --dev dumpgenesis` output: fork schedule and the system contracts (EIP-4788, 2935, 7002, 7251).
const template = JSON.parse(readFileSync(templatePath, 'utf8'));

const config = { ...template.config, chainId: CHAIN_ID, osakaTime: 0 };
config.blobSchedule = { ...config.blobSchedule, osaka: OSAKA_BLOBS };
for (const fork of POST_OSAKA_FORKS) {
    delete config[`${fork}Time`];
    delete config.blobSchedule[fork];
}

const alloc = {
    ...Object.fromEntries(Object.entries(template.alloc).filter(([, acct]) => acct.code)),
    ...readGenesisAlloc(statePath).alloc
};

const genesis = {
    config,
    nonce: '0x0',
    timestamp: '0x0',
    extraData: '0x',
    gasLimit: '0x3b9aca00',
    difficulty: '0x0',
    mixHash: `0x${'00'.repeat(32)}`,
    coinbase: `0x${'00'.repeat(20)}`,
    baseFeePerGas: '0x3b9aca00',
    alloc
};

writeFileSync(outPath, JSON.stringify(genesis, null, 1));
console.log(`wrote ${outPath}: chainId=${CHAIN_ID}, ${Object.keys(alloc).length} alloc entries`);
