// Genesis alloc for an L1 rebuilt from the anvil dump: the deployment is replayed afterwards, so only the
// CREATE2 deployer keeps its code and every EOA is funded.

import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

const CREATE2_DEPLOYER = '0x4e59b44847b379578588920ca78fbf26c0b4956c';
const EOA_BALANCE = `0x${(10n ** 24n).toString(16)}`;

export function readGenesisAlloc(statePath) {
    const dump = JSON.parse(gunzipSync(readFileSync(statePath)).toString('utf8'));
    const alloc = {};
    for (const [addr, acct] of Object.entries(dump.accounts)) {
        const hasCode = acct.code && acct.code !== '0x';
        if (addr.toLowerCase() === CREATE2_DEPLOYER) {
            alloc[addr] = { balance: acct.balance || '0x0', code: acct.code };
        } else if (!hasCode) {
            alloc[addr] = { balance: EOA_BALANCE };
        }
    }
    return { dump, alloc };
}
