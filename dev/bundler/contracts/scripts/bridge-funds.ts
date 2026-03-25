import { ETH_ADDRESS } from '@matterlabs/zksync-js/core';
import { createViemClient, createViemSdk } from '@matterlabs/zksync-js/viem';
import { createPublicClient, createWalletClient, http, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { anvil } from 'viem/chains';

// Comma-separated private keys to fund on L2. Each key pays for its own bridge from L1.
const PRIVATE_KEYS = (process.env.PRIVATE_KEYS || process.env.PRIVATE_KEY ||
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80')
    .split(',').map(k => k.trim()) as `0x${string}`[];
const L1_RPC = process.env.L1_RPC_URL || 'http://localhost:5010';
const L2_RPC = process.env.L2_RPC_URL || 'http://localhost:5050';
const BRIDGE_AMOUNT = parseEther('100');

async function bridgeIfNeeded(pk: `0x${string}`) {
    const account = privateKeyToAccount(pk);
    const l2 = createPublicClient({ transport: http(L2_RPC) });
    const balance = await l2.getBalance({ address: account.address });

    if (balance >= BRIDGE_AMOUNT / 2n) {
        console.log(`Already funded on L2: ${account.address}`);
        return;
    }

    console.log(`Bridging ETH to ${account.address}...`);
    const l1 = createPublicClient({ chain: anvil, transport: http(L1_RPC) });
    const l1Wallet = createWalletClient({ account, chain: anvil, transport: http(L1_RPC) });
    const client = createViemClient({ l1, l2, l1Wallet });
    const sdk = createViemSdk(client);
    const handle = await sdk.deposits.create({ token: ETH_ADDRESS, amount: BRIDGE_AMOUNT, to: account.address });
    await sdk.deposits.wait(handle, { for: 'l2' });
    console.log(`Bridge complete: ${account.address}`);
}

async function main() {
    for (const pk of PRIVATE_KEYS) {
        await bridgeIfNeeded(pk);
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
