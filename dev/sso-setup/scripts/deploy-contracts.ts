/**
 * Deploys the SSO system contracts to the configured sandbox chain and writes
 * their addresses to the protected runtime volume shared by the long-running services.
 *
 * Idempotent: skips contracts that already have code at their expected addresses.
 */

import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

import {
    type Abi,
    type Address,
    createPublicClient,
    createWalletClient,
    defineChain,
    type Hex,
    formatEther,
    http,
    keccak256
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

function required(name: string): string {
    const value = process.env[name]?.trim();
    if (!value) throw new Error(`${name} is required`);
    return value;
}

const SSO_DEPLOYER_PK = required('DEPLOYER_PRIVATE_KEY') as `0x${string}`;
const L2_RPC = required('RPC_URL');
const CHAIN_ID = Number(required('CHAIN_ID'));
const CHAIN_NAME = process.env.CHAIN_NAME ?? 'Prividium Sandbox';
const ENTRY_POINT_ADDRESS = (process.env.ENTRY_POINT_ADDRESS ??
    '0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108') as Address;
const MIN_L2_BALANCE = BigInt(process.env.MIN_L2_BALANCE_WEI ?? '10000000000000000');
const SSO_CLIENT_ID = process.env.SSO_CLIENT_ID ?? 'sso-sandbox-client';

const CONTRACTS_ENV_PATH = process.env.CONTRACTS_ENV_PATH ?? path.join(__dirname, '..', 'contracts.env');
const CONTRACTS_DIR = process.env.CONTRACTS_DIR ?? path.join(__dirname, '..', 'contracts');

// Load contract artifacts from Foundry out/<Name>.sol/<Name>.json structure
function loadArtifact(name: string): { abi: Abi; bytecode: { object: Hex } } {
    return JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, `${name}.sol`, `${name}.json`), 'utf8'));
}

const WebAuthnValidatorArtifact = loadArtifact('WebAuthnValidator');
const EOAKeyValidatorArtifact = loadArtifact('EOAKeyValidator');
const SessionKeyValidatorArtifact = loadArtifact('SessionKeyValidator');
const GuardianExecutorArtifact = loadArtifact('GuardianExecutor');
const ModularSmartAccountArtifact = loadArtifact('ModularSmartAccount');
const UpgradeableBeaconArtifact = loadArtifact('UpgradeableBeacon');
const MSAFactoryArtifact = loadArtifact('MSAFactory');

const MSA_FACTORY_ABI = [
    {
        type: 'function',
        name: 'deployAccount',
        inputs: [
            { name: 'salt', type: 'bytes32' },
            { name: 'initData', type: 'bytes' }
        ],
        outputs: [{ name: '', type: 'address' }],
        stateMutability: 'nonpayable'
    }
] as const;

async function assertFunded(deployer: ReturnType<typeof privateKeyToAccount>) {
    const l2 = createPublicClient({ transport: http(L2_RPC) });
    const balance = await l2.getBalance({ address: deployer.address });
    if (balance < MIN_L2_BALANCE) {
        throw new Error(
            `SSO deployer ${deployer.address} has ${formatEther(balance)} ETH; run bridge-funds before deployment`
        );
    }
    console.log(`SSO deployer funded with ${formatEther(balance)} ETH`);
}

async function deploy(
    walletClient: ReturnType<typeof createWalletClient>,
    publicClient: ReturnType<typeof createPublicClient>,
    label: string,
    abi: Abi,
    bytecode: Hex,
    args: readonly unknown[] = []
): Promise<Address> {
    const hash = await walletClient.deployContract({ abi, bytecode, args } as never);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success' || !receipt.contractAddress) {
        throw new Error(`${label} deployment failed`);
    }
    console.log(`✅ ${label}: ${receipt.contractAddress}`);
    return receipt.contractAddress as Address;
}

async function runtimeCodeHash(
    publicClient: ReturnType<typeof createPublicClient>,
    address: Address
): Promise<Hex | undefined> {
    const code = await publicClient.getBytecode({ address });
    return code && code !== '0x' ? keccak256(code) : undefined;
}

function writeEnvFile(values: Record<string, string>) {
    const content = `${Object.entries(values)
        .map(([k, v]) => `${k}=${v}`)
        .join('\n')}\n`;
    fs.mkdirSync(path.dirname(CONTRACTS_ENV_PATH), { recursive: true });
    const temporaryPath = `${CONTRACTS_ENV_PATH}.tmp`;
    fs.writeFileSync(temporaryPath, content, { mode: 0o600 });
    fs.renameSync(temporaryPath, CONTRACTS_ENV_PATH);
    fs.chmodSync(CONTRACTS_ENV_PATH, 0o600);
    console.log(`\nWritten to ${CONTRACTS_ENV_PATH}`);
}

function readExistingEnv(): Record<string, string> {
    if (!fs.existsSync(CONTRACTS_ENV_PATH)) return {};
    const content = fs.readFileSync(CONTRACTS_ENV_PATH, 'utf8');
    const result: Record<string, string> = {};
    for (const line of content.split('\n')) {
        const eq = line.indexOf('=');
        if (eq > 0) {
            result[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
        }
    }
    return result;
}

async function main() {
    const deployer = privateKeyToAccount(SSO_DEPLOYER_PK);
    console.log(`SSO deployer address: ${deployer.address}`);

    await assertFunded(deployer);

    const chain = defineChain({
        id: CHAIN_ID,
        name: CHAIN_NAME,
        nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
        rpcUrls: { default: { http: [L2_RPC] }, public: { http: [L2_RPC] } }
    });
    const transport = http(L2_RPC);
    const publicClient = createPublicClient({ chain, transport });
    const walletClient = createWalletClient({ chain, transport, account: deployer });

    // Read previously deployed addresses (if any) for idempotency
    const existing = readExistingEnv();

    async function ensure(
        key: string,
        label: string,
        abi: Abi,
        bytecode: Hex,
        args: readonly unknown[] = []
    ): Promise<Address> {
        const configured = existing[key] as Address | undefined;
        if (configured) {
            const actualCodeHash = await runtimeCodeHash(publicClient, configured);
            if (actualCodeHash) {
                const expectedCodeHash = existing[`${key}_CODE_HASH`] as Hex | undefined;
                if (!expectedCodeHash) {
                    throw new Error(
                        `${label} exists at ${configured}, but ${key}_CODE_HASH is missing; refusing to trust unknown bytecode`
                    );
                }
                if (actualCodeHash.toLowerCase() !== expectedCodeHash.toLowerCase()) {
                    throw new Error(
                        `${label} runtime bytecode mismatch at ${configured}: expected ${expectedCodeHash}, got ${actualCodeHash}`
                    );
                }
                console.log(`⏭  ${label} already verified at ${configured}`);
                return configured;
            }
        }
        const deployed = await deploy(walletClient, publicClient, label, abi, bytecode as Hex, args);
        const deployedCodeHash = await runtimeCodeHash(publicClient, deployed);
        if (!deployedCodeHash) {
            throw new Error(`No runtime bytecode at ${deployed} immediately after deploying ${label}`);
        }
        existing[key] = deployed;
        existing[`${key}_CODE_HASH`] = deployedCodeHash;
        // Persist after every transaction so a retry can verify and resume after an
        // interrupted deployment instead of creating a second contract set.
        writeEnvFile(existing);
        return deployed;
    }

    // Deployment order matches sso-deploy.ts (nonce 0–6)
    const webauthnValidator = await ensure(
        'SSO_WEBAUTHN_VALIDATOR',
        'WebAuthnValidator',
        WebAuthnValidatorArtifact.abi as Abi,
        WebAuthnValidatorArtifact.bytecode.object as Hex
    );
    const eoaValidator = await ensure(
        'SSO_EOA_VALIDATOR',
        'EOAKeyValidator',
        EOAKeyValidatorArtifact.abi as Abi,
        EOAKeyValidatorArtifact.bytecode.object as Hex
    );
    const sessionValidator = await ensure(
        'SSO_SESSION_VALIDATOR',
        'SessionKeyValidator',
        SessionKeyValidatorArtifact.abi as Abi,
        SessionKeyValidatorArtifact.bytecode.object as Hex
    );
    const guardianExecutor = await ensure(
        'SSO_GUARDIAN_EXECUTOR',
        'GuardianExecutor',
        GuardianExecutorArtifact.abi as Abi,
        GuardianExecutorArtifact.bytecode.object as Hex,
        [webauthnValidator, eoaValidator]
    );
    const accountImplementation = await ensure(
        'SSO_ACCOUNT_IMPLEMENTATION',
        'ModularSmartAccount',
        ModularSmartAccountArtifact.abi as Abi,
        ModularSmartAccountArtifact.bytecode.object as Hex
    );
    const beacon = await ensure(
        'SSO_BEACON',
        'UpgradeableBeacon',
        UpgradeableBeaconArtifact.abi as Abi,
        UpgradeableBeaconArtifact.bytecode.object as Hex,
        [accountImplementation, deployer.address]
    );
    const factory = await ensure(
        'SSO_FACTORY',
        'MSAFactory',
        MSAFactoryArtifact.abi as Abi,
        MSAFactoryArtifact.bytecode.object as Hex,
        [beacon]
    );

    // Verify EntryPoint is deployed at the expected address
    if (!(await runtimeCodeHash(publicClient, ENTRY_POINT_ADDRESS))) {
        throw new Error(`EntryPoint not found at ${ENTRY_POINT_ADDRESS} — ensure entrypoint-deployer ran first`);
    }
    console.log(`✅ EntryPoint at: ${ENTRY_POINT_ADDRESS}`);

    // Deploy a sample SSO account via factory to compute the proxy bytecode hash
    let ssoBytecodeHash = existing.DISPATCHER_SSO_BYTECODE_HASHES as string | undefined;
    if (!ssoBytecodeHash) {
        console.log('Computing SSO account bytecode hash via factory.deployAccount...');
        const salt = `0x${randomBytes(32).toString('hex')}` as Hex;
        const { request, result: deployedAccount } = await publicClient.simulateContract({
            account: deployer,
            address: factory,
            abi: MSA_FACTORY_ABI,
            functionName: 'deployAccount',
            args: [salt, '0x']
        });
        const hash = await walletClient.writeContract(request);
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        if (receipt.status !== 'success') throw new Error('factory.deployAccount failed');

        const code = await publicClient.getBytecode({ address: deployedAccount });
        if (!code || code === '0x') throw new Error(`No code at deployed SSO account: ${deployedAccount}`);
        ssoBytecodeHash = keccak256(code);
        existing.DISPATCHER_SSO_BYTECODE_HASHES = ssoBytecodeHash;
        writeEnvFile(existing);
        console.log(`✅ SSO account bytecode hash: ${ssoBytecodeHash}`);
    } else {
        console.log(`⏭  SSO bytecode hash already computed: ${ssoBytecodeHash}`);
    }

    const deployedContracts = {
        SSO_WEBAUTHN_VALIDATOR: webauthnValidator,
        SSO_EOA_VALIDATOR: eoaValidator,
        SSO_SESSION_VALIDATOR: sessionValidator,
        SSO_GUARDIAN_EXECUTOR: guardianExecutor,
        SSO_ENTRY_POINT: ENTRY_POINT_ADDRESS,
        SSO_ACCOUNT_IMPLEMENTATION: accountImplementation,
        SSO_BEACON: beacon,
        SSO_FACTORY: factory
    };
    const runtimeHashes = Object.fromEntries(
        await Promise.all(
            Object.entries(deployedContracts).map(async ([key, address]) => {
                const hash = await runtimeCodeHash(publicClient, address);
                if (!hash) throw new Error(`No runtime bytecode at ${address} while recording ${key}`);
                return [`${key}_CODE_HASH`, hash];
            })
        )
    );

    const envValues = {
        ...existing,
        // Consumed by prividium-api dispatcher
        DISPATCHER_SSO_IMPLEMENTATIONS: accountImplementation,
        DISPATCHER_SSO_BYTECODE_HASHES: ssoBytecodeHash,
        // Consumed by sso-permissions-setup and auth-server-api (SSO_* names)
        ...deployedContracts,
        // Used by this idempotent deployer to verify every existing address before skipping.
        ...runtimeHashes,
        // Consumed by auth-server-api (canonical names expected by config.ts)
        FACTORY_ADDRESS: factory,
        EOA_VALIDATOR_ADDRESS: eoaValidator,
        WEBAUTHN_VALIDATOR_ADDRESS: webauthnValidator,
        SESSION_VALIDATOR_ADDRESS: sessionValidator,
        GUARDIAN_EXECUTOR_ADDRESS: guardianExecutor,
        SSO_CLIENT_ID
    };

    writeEnvFile(envValues);

    console.log('\n📋 SSO contract deployment complete.');
    console.log('prividium-api will pick up DISPATCHER_* values from contracts.env on next start.');
}

main().catch((err) => {
    console.error('❌ SSO contract deployment failed:', err);
    process.exit(1);
});
