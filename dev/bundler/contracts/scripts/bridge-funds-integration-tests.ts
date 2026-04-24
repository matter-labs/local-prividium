// @ts-nocheck
import { ETH_ADDRESS } from '@matterlabs/zksync-js/core';
import { createViemClient, createViemSdk } from '@matterlabs/zksync-js/viem';
import { createPublicClient, createWalletClient, formatEther, http, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { anvil } from 'viem/chains';

const L1_RPC = process.env.L1_RPC_URL || 'http://localhost:5010';
const L2_RPC = process.env.L2_RPC_URL || 'http://localhost:5050';
const BRIDGE_AMOUNT = parseEther(process.env.BRIDGE_AMOUNT || '9000');
const SKIP_THRESHOLD = parseEther('10');
const POLL_INTERVAL_MS = 250;

// All default rich private keys in anvil (same as RICH_PRIVATE_KEYS in integration tests).
const RICH_PRIVATE_KEYS: `0x${string}`[] = [
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
    '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
    '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
    '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
    '0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a',
    '0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba',
    '0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e',
    '0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356',
    '0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97',
    '0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6'
];

const log = (accountIndex: number, ...msg: unknown[]) => {
    const now = new Date();
    const ts = now.toISOString().replace('T', ' ').replace('Z', '');
    console.log(`[${ts}] [Account #${accountIndex}]`, ...msg);
};

type DepositHandle = Awaited<ReturnType<ReturnType<typeof createViemSdk>['deposits']['create']>>;

/** Submit the L1 deposit tx for one account. Returns the handle, or null if already funded. */
async function createDeposit(privateKey: `0x${string}`, index: number) {
    const account = privateKeyToAccount(privateKey);
    log(index, `Address: ${account.address}`);

    const l2 = createPublicClient({ transport: http(L2_RPC) });
    const balance = await l2.getBalance({ address: account.address });
    log(index, `L2 Balance: ${formatEther(balance)} ETH`);

    if (balance > SKIP_THRESHOLD) {
        log(index, 'Already funded on L2, skipping');
        return null;
    }

    const l1 = createPublicClient({ chain: anvil, transport: http(L1_RPC) });
    const l1Wallet = createWalletClient({
        account,
        chain: anvil,
        transport: http(L1_RPC)
    });
    const l1Balance = await l1.getBalance({ address: account.address });
    log(index, `L1 Balance: ${formatEther(l1Balance)} ETH`);

    const client = createViemClient({ l1, l2, l1Wallet });
    const sdk = createViemSdk(client);

    log(index, `Bridging ${formatEther(BRIDGE_AMOUNT)} ETH from L1 to L2...`);
    const quote = await sdk.deposits.quote({
        token: ETH_ADDRESS,
        amount: BRIDGE_AMOUNT,
        to: account.address
    });
    log(index, 'Deposit quote:', {
        route: quote.route,
        transferAmount: formatEther(quote.amounts.transfer.amount),
        feeComponents: quote.fees.components
    });

    const handle = await sdk.deposits.create({
        token: ETH_ADDRESS,
        amount: BRIDGE_AMOUNT,
        to: account.address
    });
    log(index, 'Deposit handle:', {
        l1TxHash: handle.l1TxHash,
        l2TxHash: handle.l2TxHash
    });

    return { handle, sdk, index };
}

/** Poll until the L2 side of a deposit is executed. */
async function waitForL2(entry: { handle: DepositHandle; sdk: ReturnType<typeof createViemSdk>; index: number }) {
    const { handle, sdk, index } = entry;
    for (;;) {
        const status = await sdk.deposits.status(handle);
        log(index, `Deposit status: ${status.phase} l2TxHash: ${status.l2TxHash}`);

        if (status.phase === 'L2_EXECUTED') {
            break;
        }

        if (status.phase === 'L2_FAILED') {
            throw new Error(`Account #${index} deposit failed on L2: ${status.phase}`);
        }

        await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }

    await sdk.deposits.wait(handle, { for: 'l2' });
    log(index, 'Bridge complete');
}

async function main() {
    console.log(`Bridging ${formatEther(BRIDGE_AMOUNT)} ETH for ${RICH_PRIVATE_KEYS.length} accounts...`);

    // Create deposits sequentially to avoid L1 bridgehub contract reverts
    // when multiple deposit txs land in the same block.
    const pending: { handle: DepositHandle; sdk: ReturnType<typeof createViemSdk>; index: number }[] = [];
    for (let i = 0; i < RICH_PRIVATE_KEYS.length; i++) {
        const result = await createDeposit(RICH_PRIVATE_KEYS[i], i);
        if (result) {
            pending.push(result);
        }
    }

    // Wait for all L2 executions in parallel.
    if (pending.length > 0) {
        console.log(`Waiting for ${pending.length} deposits to finalize on L2...`);
        await Promise.all(pending.map(waitForL2));
    }

    console.log('All accounts bridged successfully.');
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
