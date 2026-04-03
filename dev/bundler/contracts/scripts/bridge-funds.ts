import { ETH_ADDRESS } from '@matterlabs/zksync-js/core';
import { createViemClient, createViemSdk } from '@matterlabs/zksync-js/viem';
import { createPublicClient, createWalletClient, formatEther, http, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { anvil } from 'viem/chains';

const DEPLOYER_PK = (process.env.PRIVATE_KEY ||
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80') as `0x${string}`;
const BRIDGE_SPONSOR_PK = (process.env.BRIDGE_SPONSOR_PRIVATE_KEY || DEPLOYER_PK) as `0x${string}`;
const L1_RPC = process.env.L1_RPC_URL || 'http://localhost:5010';
const L2_RPC = process.env.L2_RPC_URL || 'http://localhost:5050';
// Keep some L1 ETH for gas when creating the deposit transaction.
const BRIDGE_AMOUNT = parseEther('1');
const POLL_INTERVAL_MS = 250;

const log = (...msg) => {
    const now = new Date();
    const ts = now.toISOString().replace('T', ' ').replace('Z', '');
    console.log(`[${ts}]`, ...msg);
};

async function main() {
    const deployer = privateKeyToAccount(DEPLOYER_PK);
    const sponsor = privateKeyToAccount(BRIDGE_SPONSOR_PK);
    log(`Deployer address: ${deployer.address}`);
    log(`Bridge sponsor address: ${sponsor.address}`);

    // Check if deployer already has funds on L2
    const l2 = createPublicClient({ transport: http(L2_RPC) });
    const balance = await l2.getBalance({ address: deployer.address });
    log(`L2 Balance: ${formatEther(balance)} ETH`);

    if (balance < BRIDGE_AMOUNT / 2n) {
        const l1 = createPublicClient({ chain: anvil, transport: http(L1_RPC) });
        const l1Wallet = createWalletClient({
            account: sponsor,
            chain: anvil,
            transport: http(L1_RPC)
        });
        const sponsorBalance = await l1.getBalance({ address: sponsor.address });
        log(`Sponsor L1 balance: ${formatEther(sponsorBalance)} ETH`);

        const client = createViemClient({ l1, l2, l1Wallet });
        const sdk = createViemSdk(client);

        log(`Bridging ${formatEther(BRIDGE_AMOUNT)} ETH from L1 to L2...`);
        const quote = await sdk.deposits.quote({
            token: ETH_ADDRESS,
            amount: BRIDGE_AMOUNT,
            to: deployer.address
        });
        log('Deposit quote:', {
            route: quote.route,
            transferAmount: formatEther(quote.amounts.transfer.amount),
            feeComponents: quote.fees.components
        });

        const handle = await sdk.deposits.create({
            token: ETH_ADDRESS,
            amount: BRIDGE_AMOUNT,
            to: deployer.address
        });
        log('Deposit handle:', {
            l1TxHash: handle.l1TxHash,
            l2TxHash: handle.l2TxHash
        });

        for (;;) {
            const status = await sdk.deposits.status(handle);
            log(`Deposit status: ${status.phase} l2TxHash: ${status.l2TxHash}`);

            if (status.phase === 'L2_EXECUTED') {
                break;
            }

            if (status.phase === 'L2_FAILED') {
                throw new Error(`Deposit failed on L2: ${status.phase}`);
            }

            await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
        }

        await sdk.deposits.wait(handle, { for: 'l2' });
        log('Bridge complete');
    } else {
        log('Deployer already funded on L2');
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
