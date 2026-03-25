/**
 * Deploys the 8 SSO system contracts to the local ZKsync chain using a dedicated
 * deployer wallet (Anvil key #2). Writes the deployed addresses and bytecode hash
 * to dev/sso-setup/contracts.env so docker-compose can inject them into prividium-api.
 *
 * Idempotent: skips contracts that already have code at their expected addresses.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
import { ETH_ADDRESS } from '@matterlabs/zksync-js/core';
import { createViemClient, createViemSdk } from '@matterlabs/zksync-js/viem';
import {
  type Abi,
  type Address,
  type Hex,
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  keccak256,
  parseEther,
} from 'viem';
import { anvil } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';

// Anvil key #2 — dedicated SSO deployer, not used by any other service
const SSO_DEPLOYER_PK =
  (process.env.DEPLOYER_PRIVATE_KEY ??
    '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a') as `0x${string}`;

const L1_RPC = process.env.L1_RPC_URL ?? 'http://l1:5010';
const L2_RPC = process.env.RPC_URL ?? 'http://zksyncos:3050';
const CHAIN_ID = Number(process.env.CHAIN_ID ?? '6565');
const ENTRY_POINT_ADDRESS =
  (process.env.ENTRY_POINT_ADDRESS ?? '0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108') as Address;

const CONTRACTS_ENV_PATH = path.join(__dirname, '..', 'contracts.env');
const CONTRACTS_DIR = path.join(__dirname, '..', 'contracts');
const BRIDGE_AMOUNT = parseEther('10');

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
    inputs: [{ name: 'salt', type: 'bytes32' }, { name: 'initData', type: 'bytes' }],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'nonpayable',
  },
] as const;

async function bridgeIfNeeded(deployer: ReturnType<typeof privateKeyToAccount>) {
  const l2 = createPublicClient({ transport: http(L2_RPC) });
  const balance = await l2.getBalance({ address: deployer.address });
  if (balance >= BRIDGE_AMOUNT / 2n) {
    console.log(`SSO deployer already funded: ${deployer.address}`);
    return;
  }

  console.log(`Bridging ETH to SSO deployer: ${deployer.address}...`);
  const l1 = createPublicClient({ chain: anvil, transport: http(L1_RPC) });
  const l1Wallet = createWalletClient({ account: deployer, chain: anvil, transport: http(L1_RPC) });
  const client = createViemClient({ l1, l2: l2 as never, l1Wallet });
  const sdk = createViemSdk(client);
  const handle = await sdk.deposits.create({ token: ETH_ADDRESS, amount: BRIDGE_AMOUNT, to: deployer.address });
  await sdk.deposits.wait(handle, { for: 'l2' });
  console.log('Bridge complete');
}

async function deploy(
  walletClient: ReturnType<typeof createWalletClient>,
  publicClient: ReturnType<typeof createPublicClient>,
  label: string,
  abi: Abi,
  bytecode: Hex,
  args: readonly unknown[] = [],
): Promise<Address> {
  const hash = await walletClient.deployContract({ abi, bytecode, args } as never);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success' || !receipt.contractAddress) {
    throw new Error(`${label} deployment failed`);
  }
  console.log(`✅ ${label}: ${receipt.contractAddress}`);
  return receipt.contractAddress as Address;
}

async function hasCode(publicClient: ReturnType<typeof createPublicClient>, address: Address): Promise<boolean> {
  const code = await publicClient.getBytecode({ address });
  return !!code && code !== '0x';
}

function writeEnvFile(values: Record<string, string>) {
  const content = Object.entries(values)
    .map(([k, v]) => `${k}=${v}`)
    .join('\n') + '\n';
  fs.writeFileSync(CONTRACTS_ENV_PATH, content);
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

  await bridgeIfNeeded(deployer);

  const chain = defineChain({
    id: CHAIN_ID,
    name: 'Prividium Local',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http: [L2_RPC] }, public: { http: [L2_RPC] } },
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
    args: readonly unknown[] = [],
  ): Promise<Address> {
    const configured = existing[key] as Address | undefined;
    if (configured && await hasCode(publicClient, configured)) {
      console.log(`⏭  ${label} already at ${configured}`);
      return configured;
    }
    return deploy(walletClient, publicClient, label, abi, bytecode as Hex, args);
  }

  // Deployment order matches sso-deploy.ts (nonce 0–6)
  const webauthnValidator = await ensure(
    'SSO_WEBAUTHN_VALIDATOR', 'WebAuthnValidator',
    WebAuthnValidatorArtifact.abi as Abi, WebAuthnValidatorArtifact.bytecode.object as Hex,
  );
  const eoaValidator = await ensure(
    'SSO_EOA_VALIDATOR', 'EOAKeyValidator',
    EOAKeyValidatorArtifact.abi as Abi, EOAKeyValidatorArtifact.bytecode.object as Hex,
  );
  const sessionValidator = await ensure(
    'SSO_SESSION_VALIDATOR', 'SessionKeyValidator',
    SessionKeyValidatorArtifact.abi as Abi, SessionKeyValidatorArtifact.bytecode.object as Hex,
  );
  const guardianExecutor = await ensure(
    'SSO_GUARDIAN_EXECUTOR', 'GuardianExecutor',
    GuardianExecutorArtifact.abi as Abi, GuardianExecutorArtifact.bytecode.object as Hex,
    [webauthnValidator, eoaValidator],
  );
  const accountImplementation = await ensure(
    'SSO_ACCOUNT_IMPLEMENTATION', 'ModularSmartAccount',
    ModularSmartAccountArtifact.abi as Abi, ModularSmartAccountArtifact.bytecode.object as Hex,
  );
  const beacon = await ensure(
    'SSO_BEACON', 'UpgradeableBeacon',
    UpgradeableBeaconArtifact.abi as Abi, UpgradeableBeaconArtifact.bytecode.object as Hex,
    [accountImplementation, deployer.address],
  );
  const factory = await ensure(
    'SSO_FACTORY', 'MSAFactory',
    MSAFactoryArtifact.abi as Abi, MSAFactoryArtifact.bytecode.object as Hex,
    [beacon],
  );

  // Verify EntryPoint is deployed at the expected address
  if (!await hasCode(publicClient, ENTRY_POINT_ADDRESS)) {
    throw new Error(`EntryPoint not found at ${ENTRY_POINT_ADDRESS} — ensure entrypoint-deployer ran first`);
  }
  console.log(`✅ EntryPoint at: ${ENTRY_POINT_ADDRESS}`);

  // Deploy a sample SSO account via factory to compute the proxy bytecode hash
  let ssoBytecodeHash = existing['DISPATCHER_SSO_BYTECODE_HASHES'] as string | undefined;
  if (!ssoBytecodeHash) {
    console.log('Computing SSO account bytecode hash via factory.deployAccount...');
    const salt = `0x${randomBytes(32).toString('hex')}` as Hex;
    const { request, result: deployedAccount } = await publicClient.simulateContract({
      account: deployer,
      address: factory,
      abi: MSA_FACTORY_ABI,
      functionName: 'deployAccount',
      args: [salt, '0x'],
    });
    const hash = await walletClient.writeContract(request);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('factory.deployAccount failed');

    const code = await publicClient.getBytecode({ address: deployedAccount });
    if (!code || code === '0x') throw new Error(`No code at deployed SSO account: ${deployedAccount}`);
    ssoBytecodeHash = keccak256(code);
    console.log(`✅ SSO account bytecode hash: ${ssoBytecodeHash}`);
  } else {
    console.log(`⏭  SSO bytecode hash already computed: ${ssoBytecodeHash}`);
  }

  const envValues = {
    // Consumed by prividium-api dispatcher
    DISPATCHER_SSO_IMPLEMENTATIONS: accountImplementation,
    DISPATCHER_SSO_BYTECODE_HASHES: ssoBytecodeHash,
    // Consumed by sso-permissions-setup and auth-server-api (SSO_* names)
    SSO_WEBAUTHN_VALIDATOR: webauthnValidator,
    SSO_EOA_VALIDATOR: eoaValidator,
    SSO_SESSION_VALIDATOR: sessionValidator,
    SSO_GUARDIAN_EXECUTOR: guardianExecutor,
    SSO_ENTRY_POINT: ENTRY_POINT_ADDRESS,
    SSO_ACCOUNT_IMPLEMENTATION: accountImplementation,
    SSO_BEACON: beacon,
    SSO_FACTORY: factory,
    // Consumed by auth-server-api (canonical names expected by config.ts)
    FACTORY_ADDRESS: factory,
    EOA_VALIDATOR_ADDRESS: eoaValidator,
    WEBAUTHN_VALIDATOR_ADDRESS: webauthnValidator,
    SESSION_VALIDATOR_ADDRESS: sessionValidator,
    GUARDIAN_EXECUTOR_ADDRESS: guardianExecutor,
  };

  writeEnvFile(envValues);

  console.log('\n📋 SSO contract deployment complete.');
  console.log('prividium-api will pick up DISPATCHER_* values from contracts.env on next start.');
}

main().catch((err) => {
  console.error('❌ SSO contract deployment failed:', err);
  process.exit(1);
});
