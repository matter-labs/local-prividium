/**
 * Seeds SSO infrastructure directly into the Prividium postgres database:
 *   1. Registers 8 SSO system contracts with public permissions (all functions)
 *   2. Creates the `sso-smart-account` permission template with only the 5
 *      read functions per the auth-server-api README (ENTRY_POINT_V08, accountId,
 *      domainSeparator, eip712Domain, entryPoint) plus receive() for ETH transfers
 *   3. Creates the `erc-20` template for mintable ERC-20 tokens (used by example apps)
 *   4. Creates the OAuth app for auth-server; appends SSO_CLIENT_ID to contracts.env
 *   5. Seeds base users (user1@local.dev, user2@local.dev) matching the local Keycloak realm
 *
 * Idempotent: uses ON CONFLICT DO NOTHING / DO UPDATE.
 * Bypasses the Prividium API entirely — no auth required.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import postgres from 'postgres';
import type { Abi, AbiFunction } from 'viem';
import { parseAbi, toFunctionSelector } from 'viem';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONTRACTS_ENV_PATH = path.join(__dirname, '..', 'contracts.env');
const CONTRACTS_DIR = path.join(__dirname, '..', 'contracts');

const DATABASE_URL = process.env.DATABASE_URL ?? 'postgres://postgres:postgres@postgres:5432/prividium_api';

// Fixed client ID written to contracts.env so auth-server can pick it up
const SSO_CLIENT_ID = 'sso-local-client';
const SSO_APP_ID = 'sso-local-app';

// Only these 5 functions on SSO smart accounts need public read access.
// Write functions (execute, executeUserOp, etc.) go through the ERC-4337
// bundler → EntryPoint path and are not subject to Prividium's RPC proxy
// permission checks. See auth-server-api README for reference.
const SSO_SMART_ACCOUNT_PUBLIC_FUNCTIONS = new Set([
    'ENTRY_POINT_V08',
    'accountId',
    'domainSeparator',
    'eip712Domain',
    'entryPoint'
]);

// receive() needs public write access so accounts can receive ETH directly.
// It has no 4-byte selector — stored as empty bytea ('0x') in the DB.
const SSO_SMART_ACCOUNT_PUBLIC_RECEIVE = true;

// ─── Helpers ─────────────────────────────────────────────────────────────────

function addr(hex: string): Buffer {
    return Buffer.from(hex.replace('0x', '').toLowerCase(), 'hex');
}

function sel(hex: string): Buffer {
    return Buffer.from(hex.replace('0x', ''), 'hex');
}

function readEnv(): Record<string, string> {
    if (!fs.existsSync(CONTRACTS_ENV_PATH)) return {};
    return Object.fromEntries(
        fs
            .readFileSync(CONTRACTS_ENV_PATH, 'utf8')
            .split('\n')
            .filter((l) => l.includes('='))
            .map((l) => {
                const eq = l.indexOf('=');
                return [l.slice(0, eq).trim(), l.slice(eq + 1).trim()];
            })
    );
}

function appendEnv(key: string, value: string) {
    const content = fs.existsSync(CONTRACTS_ENV_PATH) ? fs.readFileSync(CONTRACTS_ENV_PATH, 'utf8') : '';
    if (content.includes(`${key}=`)) {
        const updated = content
            .split('\n')
            .map((l) => (l.startsWith(`${key}=`) ? `${key}=${value}` : l))
            .join('\n');
        fs.writeFileSync(CONTRACTS_ENV_PATH, updated);
    } else {
        fs.appendFileSync(CONTRACTS_ENV_PATH, `\n${key}=${value}\n`);
    }
}

function loadArtifact(name: string): { abi: Abi } {
    return JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, `${name}.sol`, `${name}.json`), 'utf8'));
}

function formatSig(item: AbiFunction): string {
    const params = item.inputs.map((i) => (i.name ? `${i.type} ${i.name}` : i.type)).join(', ');
    return `function ${item.name}(${params})`;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
    const env = readEnv();

    const ssoContracts = [
        {
            key: 'SSO_WEBAUTHN_VALIDATOR',
            name: 'SSO WebAuthn Validator',
            artifact: 'WebAuthnValidator',
            description: 'Validator module for WebAuthn passkey authentication.'
        },
        {
            key: 'SSO_EOA_VALIDATOR',
            name: 'SSO EOA Validator',
            artifact: 'EOAKeyValidator',
            description: 'Validator module for EOA-based signatures.'
        },
        {
            key: 'SSO_SESSION_VALIDATOR',
            name: 'SSO Session Validator',
            artifact: 'SessionKeyValidator',
            description: 'Validator module for session keys.'
        },
        {
            key: 'SSO_GUARDIAN_EXECUTOR',
            name: 'SSO Guardian Executor',
            artifact: 'GuardianExecutor',
            description: 'Executor module for guardian-based recovery.'
        },
        {
            key: 'SSO_ENTRY_POINT',
            name: 'SSO EntryPoint',
            artifact: 'EntryPoint',
            description: 'ERC-4337 EntryPoint used by SSO smart accounts.'
        },
        {
            key: 'SSO_ACCOUNT_IMPLEMENTATION',
            name: 'SSO Account Implementation',
            artifact: 'ModularSmartAccount',
            description: 'ZKsync SSO Modular Smart Account implementation.'
        },
        {
            key: 'SSO_BEACON',
            name: 'SSO Account Beacon',
            artifact: 'UpgradeableBeacon',
            description: 'Upgradeable beacon for SSO smart accounts.'
        },
        {
            key: 'SSO_FACTORY',
            name: 'SSO Account Factory',
            artifact: 'MSAFactory',
            description: 'Factory for deploying SSO smart account beacon proxies.'
        }
    ] as const;

    for (const { key } of ssoContracts) {
        if (!env[key]) throw new Error(`Missing ${key} in contracts.env — run deploy-contracts first`);
    }

    const sql = postgres(DATABASE_URL);

    try {
        // ── 1. Contracts + function permissions ──────────────────────────────────
        for (const { key, name, artifact, description } of ssoContracts) {
            const address = env[key]!;
            const { abi } = loadArtifact(artifact);
            const addrBuf = addr(address);

            await sql`
        INSERT INTO contracts (contract_address, name, description, abi, disclose_bytecode, disclose_erc_20_total_supply, is_system_contract)
        VALUES (${addrBuf}, ${name}, ${description}, ${JSON.stringify(abi)}, false, false, false)
        ON CONFLICT (contract_address) DO NOTHING
      `;

            for (const item of abi) {
                if ((item as { type: string }).type !== 'function') continue;
                const fn = item as AbiFunction;
                const selector = toFunctionSelector(fn);
                const selBuf = sel(selector);
                const signature = formatSig(fn);
                const accessType = fn.stateMutability === 'view' || fn.stateMutability === 'pure' ? 'read' : 'write';

                await sql`
          INSERT INTO contract_function_permissions
            (contract_address, method_selector, function_signature, access_type, rule_type)
          VALUES (${addrBuf}, ${selBuf}, ${signature}, ${accessType}, 'public')
          ON CONFLICT (contract_address, method_selector) DO NOTHING
        `;
            }

            console.log(`✅ Seeded contract: ${name}`);
        }

        // ── 2. Template ──────────────────────────────────────────────────────────
        const { abi: msaAbi } = loadArtifact('ModularSmartAccount');

        const [template] = await sql<[{ id: number }]>`
      INSERT INTO contract_templates (template_key, name, description, abi)
      VALUES (
        'sso-smart-account',
        'ZKsync SSO Smart Account',
        'Permission template for ZKsync SSO modular smart accounts deployed by auth-server-api',
        ${JSON.stringify(msaAbi)}
      )
      ON CONFLICT (template_key) DO UPDATE SET template_key = EXCLUDED.template_key
      RETURNING id
    `;

        const templateId = template.id;

        // Only seed the 5 functions that require public read access per the README.
        // Remove any extra permissions that may have been seeded in a previous run.
        await sql`
      DELETE FROM contract_template_permissions
      WHERE template_id = ${templateId}
    `;

        for (const item of msaAbi) {
            if ((item as { type: string }).type !== 'function') continue;
            const fn = item as AbiFunction;
            if (!SSO_SMART_ACCOUNT_PUBLIC_FUNCTIONS.has(fn.name)) continue;

            const selector = toFunctionSelector(fn);
            const selBuf = sel(selector);
            const signature = formatSig(fn);

            await sql`
        INSERT INTO contract_template_permissions
          (template_id, method_selector, function_signature, access_type, rule_type)
        VALUES (${templateId}, ${selBuf}, ${signature}, 'read', 'public')
        ON CONFLICT (template_id, method_selector) DO NOTHING
      `;
        }

        // receive() — empty bytea selector, allows direct ETH transfers to the account
        if (SSO_SMART_ACCOUNT_PUBLIC_RECEIVE) {
            await sql`
        INSERT INTO contract_template_permissions
          (template_id, method_selector, function_signature, access_type, rule_type)
        VALUES (${templateId}, ''::bytea, 'receive()', 'write', 'public')
        ON CONFLICT (template_id, method_selector) DO NOTHING
      `;
        }

        console.log(`✅ Seeded template: sso-smart-account (id=${templateId}, 5 public read + receive)`);

        // ── 3. ERC-20 (Mintable) template ─────────────────────────────────────────
        // Shared template used by example apps that deploy mintable ERC-20 tokens.
        // Functions with restrictArgument enforce that argument 0 == caller address.
        const ERC20_MINTABLE_ABI = parseAbi([
            'function allowance(address owner, address spender) view returns (uint256)',
            'function approve(address spender, uint256 value) returns (bool)',
            'function balanceOf(address account) view returns (uint256)',
            'function decimals() view returns (uint8)',
            'function mint(address _to, uint256 _amount) returns (bool)',
            'function name() view returns (string)',
            'function symbol() view returns (string)',
            'function totalSupply() view returns (uint256)',
            'function transfer(address to, uint256 value) returns (bool)',
            'function transferFrom(address from, address to, uint256 value) returns (bool)'
        ]);

        // Functions where access is restricted to callers whose address matches argument 0.
        const ERC20_RESTRICT_ARG: Record<string, number> = {
            allowance: 0,
            balanceOf: 0,
            mint: 0,
            transferFrom: 0
        };

        const [erc20Template] = await sql<[{ id: number }]>`
      INSERT INTO contract_templates (template_key, name, description, abi)
      VALUES (
        'erc-20',
        'ERC-20 (Mintable)',
        'Standard mintable ERC-20 token template. Restricted functions require the caller to match argument 0.',
        ${JSON.stringify(ERC20_MINTABLE_ABI)}
      )
      ON CONFLICT (template_key) DO UPDATE SET template_key = EXCLUDED.template_key
      RETURNING id
    `;

        const erc20TemplateId = erc20Template.id;

        for (const item of ERC20_MINTABLE_ABI) {
            if ((item as { type: string }).type !== 'function') continue;
            const fn = item as AbiFunction;
            const selector = toFunctionSelector(fn);
            const selBuf = sel(selector);
            const signature = formatSig(fn);
            const accessType = fn.stateMutability === 'view' || fn.stateMutability === 'pure' ? 'read' : 'write';
            const argIndex = ERC20_RESTRICT_ARG[fn.name] ?? null;
            const ruleType = argIndex !== null ? 'restrictArgument' : 'public';

            const [perm] = await sql<[{ id: number }]>`
        INSERT INTO contract_template_permissions
          (template_id, method_selector, function_signature, access_type, rule_type)
        VALUES (${erc20TemplateId}, ${selBuf}, ${signature}, ${accessType}, ${ruleType})
        ON CONFLICT (template_id, method_selector) DO UPDATE SET
          rule_type = EXCLUDED.rule_type,
          access_type = EXCLUDED.access_type
        RETURNING id
      `;

            if (argIndex !== null) {
                await sql`
          INSERT INTO contract_template_argument_restrictions (permission_id, argument_index)
          VALUES (${perm.id}, ${argIndex})
          ON CONFLICT (permission_id, argument_index) DO NOTHING
        `;
            }
        }

        const erc20FnCount = ERC20_MINTABLE_ABI.filter((i) => i.type === 'function').length;
        console.log(`✅ Seeded template: erc-20 (id=${erc20TemplateId}, ${erc20FnCount} functions)`);

        // ── 4. OAuth app for auth-server ─────────────────────────────────────────
        await sql`
      INSERT INTO applications (id, name, description, oauth_client_id, oauth_redirect_uris, origin, is_public)
      VALUES (
        ${SSO_APP_ID},
        'ZKsync SSO Auth Server',
        'Web application for creating and managing passkey-based ZKsync SSO smart account wallets. Users can register WebAuthn passkeys, deploy smart accounts, and manage their wallet settings.',
        ${SSO_CLIENT_ID},
        ARRAY['http://localhost:3006/callback']::text[],
        'http://localhost:3006',
        true
      )
      ON CONFLICT (oauth_client_id) DO UPDATE SET
        is_public = true,
        description = EXCLUDED.description
    `;

        appendEnv('SSO_CLIENT_ID', SSO_CLIENT_ID);

        console.log(`✅ Seeded OAuth app: clientId=${SSO_CLIENT_ID}`);
        // ── 5. Base users (matching local Keycloak realm) ─────────────────────────
        // These users exist in realm-export.json with fixed sub UUIDs.
        // Seeded here so example apps can link wallets without re-creating the user records.
        const BASE_USERS = [
            { id: 'local-user1', display: 'user1@local.dev', sub: '00000000-0000-0000-0000-000000000004' },
            { id: 'local-user2', display: 'user2@local.dev', sub: '00000000-0000-0000-0000-000000000005' }
        ];

        for (const user of BASE_USERS) {
            await sql`
        INSERT INTO users (id, display_name, oidc_sub, source)
        VALUES (${user.id}, ${user.display}, ${user.sub}, 'oidc')
        ON CONFLICT (id) DO NOTHING
      `;
            console.log(`✅ Base user: ${user.display}`);
        }

        console.log(`\n✅ Core permissions seed complete (SSO + ERC-20 template + base users).`);
    } finally {
        await sql.end();
    }
}

main().catch((err) => {
    console.error('❌ SSO seed failed:', err);
    process.exit(1);
});
