import { ETH_ADDRESS } from '@matterlabs/zksync-js/core';
import { createViemClient, createViemSdk } from '@matterlabs/zksync-js/viem';
import { createPublicClient, createWalletClient, formatEther, http, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

function required(name: string): string {
    const value = process.env[name]?.trim();
    if (!value) throw new Error(`${name} is required`);
    return value;
}

const PRIVATE_KEYS = required('PRIVATE_KEYS')
    .split(',')
    .map((key) => key.trim())
    .filter(Boolean) as `0x${string}`[];
const BRIDGE_SPONSOR_PK = required('BRIDGE_SPONSOR_PRIVATE_KEY') as `0x${string}`;
const L1_RPC = required('L1_RPC_URL');
const L2_RPC = required('L2_RPC_URL');
const L2_CHAIN_ID = Number(required('L2_CHAIN_ID'));
const TARGET_BALANCE = parseEther(process.env.TARGET_L2_BALANCE_ETH ?? '0.05');
const POLL_INTERVAL_MS = Number(process.env.DEPOSIT_POLL_INTERVAL_MS ?? '12000');

if (!Number.isSafeInteger(L2_CHAIN_ID) || L2_CHAIN_ID <= 0) {
    throw new Error('L2_CHAIN_ID must be a positive safe integer');
}
if (PRIVATE_KEYS.length === 0) {
    throw new Error('PRIVATE_KEYS must contain at least one service-wallet key');
}

const log = (...message: unknown[]) => {
    console.log(`[${new Date().toISOString()}]`, ...message);
};

async function bridgeIfNeeded(targetPrivateKey: `0x${string}`, sponsorPrivateKey: `0x${string}`) {
    const target = privateKeyToAccount(targetPrivateKey);
    const sponsor = privateKeyToAccount(sponsorPrivateKey);
    const l2 = createPublicClient({ transport: http(L2_RPC) });

    const actualL2ChainId = await l2.getChainId();
    if (actualL2ChainId !== L2_CHAIN_ID) {
        throw new Error(`L2 RPC chain ID ${actualL2ChainId} does not match ${L2_CHAIN_ID}`);
    }

    const balance = await l2.getBalance({ address: target.address });
    log(`${target.address} L2 balance: ${formatEther(balance)} ETH`);
    if (balance >= TARGET_BALANCE) {
        log(`${target.address} is already at or above the ${formatEther(TARGET_BALANCE)} ETH target`);
        return;
    }

    const amount = TARGET_BALANCE - balance;
    const l1 = createPublicClient({ chain: sepolia, transport: http(L1_RPC) });
    const actualL1ChainId = await l1.getChainId();
    if (actualL1ChainId !== sepolia.id) {
        throw new Error(`L1 RPC chain ID ${actualL1ChainId} is not Sepolia (${sepolia.id})`);
    }

    const l1Wallet = createWalletClient({
        account: sponsor,
        chain: sepolia,
        transport: http(L1_RPC)
    });
    const sponsorBalance = await l1.getBalance({ address: sponsor.address });
    log(`Bridge sponsor ${sponsor.address} L1 balance: ${formatEther(sponsorBalance)} ETH`);

    const client = createViemClient({ l1, l2, l1Wallet });
    const sdk = createViemSdk(client);
    const quote = await sdk.deposits.quote({
        token: ETH_ADDRESS,
        amount,
        to: target.address
    });

    log(`Bridging ${formatEther(amount)} ETH to ${target.address}`, {
        route: quote.route,
        transferAmount: formatEther(quote.amounts.transfer.amount),
        feeComponents: quote.fees.components
    });

    const handle = await sdk.deposits.create({
        token: ETH_ADDRESS,
        amount,
        to: target.address
    });
    log('Deposit submitted', { l1TxHash: handle.l1TxHash, l2TxHash: handle.l2TxHash });

    for (;;) {
        const status = await sdk.deposits.status(handle);
        log(`Deposit status for ${target.address}: ${status.phase}`);
        if (status.phase === 'L2_EXECUTED') break;
        if (status.phase === 'L2_FAILED') throw new Error(`Deposit failed for ${target.address}`);
        await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }

    await sdk.deposits.wait(handle, { for: 'l2' });
    log(`Funding target reached for ${target.address}`);
}

async function main() {
    const uniqueKeys = [...new Set(PRIVATE_KEYS.map((key) => key.toLowerCase()))] as `0x${string}`[];
    for (const key of uniqueKeys) {
        await bridgeIfNeeded(key, BRIDGE_SPONSOR_PK);
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
