import { readFile } from "node:fs/promises";
import { createServer } from "node:http";

const port = Number(process.env.PORT ?? "9102");
const rpcUrl = process.env.L1_RPC_URL;
const manifestPath = process.env.MANIFEST_PATH ?? "/public/manifest.json";

if (!rpcUrl) {
  throw new Error("L1_RPC_URL is required");
}

async function rpc(method, params) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  if (!response.ok) {
    throw new Error(`L1 RPC returned HTTP ${response.status}`);
  }
  const payload = await response.json();
  if (payload.error) {
    throw new Error(payload.error.message ?? JSON.stringify(payload.error));
  }
  return payload.result;
}

async function metrics() {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const operators = manifest.operator_addresses ?? {};
  const lines = [
    "# HELP prividium_operator_l1_balance_eth Sepolia ETH held by a ZKsync OS operator.",
    "# TYPE prividium_operator_l1_balance_eth gauge",
  ];

  for (const [role, address] of Object.entries(operators)) {
    if (!/^0x[0-9a-fA-F]{40}$/.test(address)) continue;
    const balanceWei = BigInt(await rpc("eth_getBalance", [address, "latest"]));
    const whole = balanceWei / 10n ** 18n;
    const fraction = (balanceWei % 10n ** 18n).toString().padStart(18, "0");
    lines.push(`prividium_operator_l1_balance_eth{role="${role}"} ${whole}.${fraction}`);
  }

  return `${lines.join("\n")}\n`;
}

createServer(async (request, response) => {
  if (request.url !== "/metrics") {
    response.writeHead(404).end();
    return;
  }
  try {
    response.writeHead(200, { "content-type": "text/plain; version=0.0.4" });
    response.end(await metrics());
  } catch (error) {
    response.writeHead(503, { "content-type": "text/plain" });
    response.end(`operator balance scrape failed: ${error.message}\n`);
  }
}).listen(port, "0.0.0.0");
