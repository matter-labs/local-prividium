// Builds the `besu operator generate-blockchain-config` input from the anvil L1 dump.
// Usage: node generate-besu-genesis.mjs <l1-state.json.gz> <out-network-config.json>

import { writeFileSync } from 'node:fs';
import { readGenesisAlloc } from '../l1-genesis-alloc.mjs';

const [, , statePath, outPath] = process.argv;
if (!statePath || !outPath) {
    console.error('usage: generate-besu-genesis.mjs <l1-state.json.gz> <out-network-config.json>');
    process.exit(1);
}

const { alloc } = readGenesisAlloc(statePath);

const networkConfig = {
    genesis: {
        config: {
            chainId: 31337,
            homesteadBlock: 0,
            eip150Block: 0,
            eip155Block: 0,
            eip158Block: 0,
            byzantiumBlock: 0,
            constantinopleBlock: 0,
            petersburgBlock: 0,
            istanbulBlock: 0,
            berlinBlock: 0,
            londonBlock: 0,
            shanghaiTime: 0,
            cancunTime: 0, // EIP-4844 blobs
            zeroBaseFee: true,
            qbft: {
                blockperiodseconds: 1,
                epochlength: 30000,
                requesttimeoutseconds: 4
            }
        },
        nonce: '0x0',
        timestamp: '0x0',
        gasLimit: '0x3b9aca00',
        difficulty: '0x1',
        mixHash: '0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365', // QBFT sentinel

        coinbase: '0x0000000000000000000000000000000000000000',
        alloc
    },
    blockchain: {
        nodes: {
            generate: true,
            count: 1
        }
    }
};

writeFileSync(outPath, `${JSON.stringify(networkConfig, null, 2)}\n`);
const contracts = Object.values(alloc).filter((a) => a.code).length;
console.log(
    `Wrote ${outPath}: ${Object.keys(alloc).length} alloc entries (${contracts} predeploy), chainId 31337, QBFT single-validator`
);
