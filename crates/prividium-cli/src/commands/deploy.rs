use std::{fs, net::ToSocketAddrs, time::Duration};

use chrono::Utc;
use serde_json::Value;
use tokio::time::{Instant, sleep};

use crate::{
    cli::ProfileArgs,
    compose::{Compose, ensure_nonempty_regular},
    config::{RuntimeConfig, validate_profile},
    context::Context,
    error::{AppError, Result},
    fs::atomic_write,
    output::{Artifact, Check, CheckStatus, CommandOutcome, Reporter},
    process::CommandSpec,
    runtime::{load_runtime, sha256_file},
};

const LONG_RUNNING: &[&str] = &[
    "zksyncos",
    "postgres",
    "keycloak",
    "prividium-api",
    "user-panel",
    "admin-panel",
    "caddy",
    "block-explorer-api",
    "block-explorer-app",
    "block-explorer-worker",
    "block-explorer-data-fetcher",
    "prometheus",
    "grafana",
    "operator-balance-exporter",
];

pub async fn run(
    context: &Context,
    reporter: &Reporter,
    args: ProfileArgs,
) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    let config = load_runtime(context)?;
    let domain = config.required("SANDBOX_DOMAIN")?;
    let unresolved = unresolved_dns(domain).await;
    if !unresolved.is_empty() {
        return Err(AppError::action(
            "DNS_REQUIRED",
            format!(
                "configure all public sandbox DNS names before deployment: {}",
                unresolved.join(", ")
            ),
            Some("prividiumcli deploy"),
        ));
    }
    validate_runtime_artifacts(context, &config)?;
    render_browser_config(context, &config)?;
    let prepared_image = validate_public_manifest(context, &config)?;
    let compose = Compose::new(context, context.runtime_environment());
    compose.validate().await?;
    for image in compose.images(Some(&prepared_image)).await? {
        let inspect = CommandSpec::new("docker")
            .args(["image", "inspect", image.as_str()])
            .output("prepared image inventory")
            .await?;
        if !inspect.status.success() {
            return Err(AppError::action(
                "PREPARED_STACK_IMAGE_MISSING",
                format!("prepared stack image is missing: {image}"),
                Some("prividiumcli prepare"),
            ));
        }
    }
    reporter.progress("Starting the prebuilt 14-service core stack...");
    compose.up(&prepared_image).await?;
    reporter.progress("Waiting for core services and public interfaces...");
    if let Err(error) = wait_for_readiness(&compose, &config, reporter).await {
        write_incomplete_summary(context, &config, &error.message)?;
        return Err(error);
    }
    let summary = deployment_summary(context, &config)?;
    atomic_write(
        &context.public("deployment-summary.md"),
        0o644,
        summary.as_bytes(),
        true,
    )?;
    let incomplete = context
        .runtime_dir
        .join("reports/deployment-summary.incomplete.md");
    if incomplete.is_file() {
        fs::remove_file(&incomplete).map_err(|error| {
            AppError::failed("INCOMPLETE_SUMMARY_REMOVE_FAILED", error.to_string())
        })?;
    }
    let mut outcome = CommandOutcome::complete(
        "deploy",
        "Core Prividium sandbox is healthy and ready for the authenticated product smoke.",
    )
    .next("prividiumcli verify", true);
    outcome.checks = vec![
        pass(
            "services",
            "14 long-running services are ready and chain-preflight completed",
        ),
        pass(
            "https",
            "user, admin, Explorer, API, and OIDC endpoints are ready",
        ),
        pass(
            "protected_rpc",
            "unauthenticated protected RPC requests are denied",
        ),
    ];
    outcome.artifacts.push(Artifact {
        kind: "deployment_summary".to_owned(),
        path: "deployment/public/deployment-summary.md".to_owned(),
    });
    outcome.data = Some(serde_json::json!({
        "l1_chain_id": 11155111,
        "l2_chain_id": config.l2_chain_id()?,
        "service_count": 14,
        "profile": "sandbox",
        "core_only": true,
    }));
    Ok(outcome)
}

fn validate_runtime_artifacts(context: &Context, config: &RuntimeConfig) -> Result<()> {
    for relative in [
        "chain/server.yaml",
        "chain/sandbox-overrides.yaml",
        "chain/genesis.json",
        "chain/state.json",
        "chain/out/manifest.json",
        "chain/out/preparation.json",
    ] {
        ensure_nonempty_regular(&context.runtime_dir.join(relative), relative)?;
    }
    if config.required("RUNTIME_DIR")? != "/etc/prividium/runtime" {
        return Err(AppError::failed(
            "INVALID_RUNTIME_DIRECTORY",
            "RUNTIME_DIR must be /etc/prividium/runtime",
        ));
    }
    Ok(())
}

fn validate_public_manifest(context: &Context, config: &RuntimeConfig) -> Result<String> {
    let manifest_path = context.public("manifest.json");
    ensure_nonempty_regular(&manifest_path, "public manifest")?;
    let manifest: Value = serde_json::from_slice(
        &fs::read(&manifest_path)
            .map_err(|error| AppError::failed("PUBLIC_MANIFEST_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("PUBLIC_MANIFEST_INVALID", error.to_string()))?;
    let chain_id = config.l2_chain_id()?;
    let genesis_sha = sha256_file(&context.runtime_dir.join("chain/genesis.json"))?;
    let valid = manifest.get("environment").and_then(Value::as_str) == Some("sandbox")
        && manifest.get("l1_chain_id").and_then(Value::as_u64) == Some(11_155_111)
        && manifest.get("l2_chain_id").and_then(Value::as_u64) == Some(chain_id)
        && manifest.get("protocol_version").and_then(Value::as_str) == Some("0.31.0")
        && manifest
            .pointer("/assets/base_token")
            .and_then(Value::as_str)
            == Some("ETH")
        && manifest
            .pointer("/assets/protocol_fee_asset")
            .and_then(Value::as_str)
            == Some("ETH")
        && manifest
            .pointer("/sources/protocol")
            .and_then(Value::as_str)
            == Some("e091691063c99a1d0281d6fe42fb0ec4430f3673")
        && manifest
            .pointer("/sources/zk_deployer")
            .and_then(Value::as_str)
            == Some("16c6a83b4f634609958f347c56549ba19bf9df9b")
        && manifest.pointer("/genesis/sha256").and_then(Value::as_str)
            == Some(genesis_sha.as_str())
        && manifest
            .pointer("/data_availability/mode")
            .and_then(Value::as_str)
            == Some("no_da")
        && manifest
            .pointer("/data_availability/type")
            .and_then(Value::as_str)
            == Some("validium")
        && manifest
            .pointer("/transaction_filterer/chain_admin_whitelisted")
            .and_then(Value::as_bool)
            == Some(true)
        && manifest
            .pointer("/transaction_filterer/deposits_allowed")
            .and_then(Value::as_bool)
            == Some(true)
        && manifest.pointer("/security/proofs").and_then(Value::as_str) == Some("fake")
        && manifest
            .pointer("/security/verifier")
            .and_then(Value::as_str)
            == Some("testnet")
        && manifest
            .pointer("/security/production_safe")
            .and_then(Value::as_bool)
            == Some(false);
    if !valid {
        return Err(AppError::failed(
            "PUBLIC_MANIFEST_MISMATCH",
            "public manifest does not match the protected sandbox runtime",
        ));
    }
    let preparation: Value = serde_json::from_slice(
        &fs::read(context.runtime_dir.join("chain/out/preparation.json"))
            .map_err(|error| AppError::failed("PREPARATION_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("PREPARATION_INVALID", error.to_string()))?;
    preparation
        .get("chain_bootstrap_image_id")
        .and_then(Value::as_str)
        .filter(|value| {
            value.strip_prefix("sha256:").is_some_and(|digest| {
                digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
            })
        })
        .map(str::to_owned)
        .ok_or_else(|| {
            AppError::failed("PREPARATION_INVALID", "prepared image identity is missing")
        })
}

fn render_browser_config(context: &Context, config: &RuntimeConfig) -> Result<()> {
    let template = fs::read_to_string(
        context
            .repo_root
            .join("dev/block-explorer/block-explorer-config.template.js"),
    )
    .map_err(|error| AppError::failed("BROWSER_CONFIG_TEMPLATE_MISSING", error.to_string()))?;
    let rendered = template
        .replace("__SANDBOX_DOMAIN__", config.required("SANDBOX_DOMAIN")?)
        .replace("__L2_CHAIN_ID__", &config.l2_chain_id()?.to_string())
        .replace("__CHAIN_NAME__", config.required("CHAIN_NAME")?);
    atomic_write(
        &context.runtime_dir.join("block-explorer-config.js"),
        0o600,
        rendered.as_bytes(),
        true,
    )
}

async fn wait_for_readiness(
    compose: &Compose<'_>,
    config: &RuntimeConfig,
    reporter: &Reporter,
) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(600);
    loop {
        let service_failures = service_failures(compose).await?;
        if service_failures.is_empty() {
            break;
        }
        if Instant::now() >= deadline {
            return Err(AppError::failed(
                "CORE_SERVICES_NOT_READY",
                format!(
                    "core services did not become ready: {}",
                    service_failures.join(", ")
                ),
            ));
        }
        reporter.progress(format!(
            "Waiting for core services: {}",
            service_failures.join(", ")
        ));
        sleep(Duration::from_secs(10)).await;
    }
    loop {
        let endpoint_failures = endpoint_failures(config).await;
        if endpoint_failures.is_empty() {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(AppError::failed(
                "PUBLIC_ENDPOINTS_NOT_READY",
                format!(
                    "public interfaces did not become ready: {}",
                    endpoint_failures.join(", ")
                ),
            ));
        }
        reporter.progress(format!(
            "Waiting for public interfaces: {}",
            endpoint_failures.join(", ")
        ));
        sleep(Duration::from_secs(10)).await;
    }
}

async fn service_failures(compose: &Compose<'_>) -> Result<Vec<String>> {
    let mut failures = Vec::new();
    for service in LONG_RUNNING {
        let Some(id) = compose.service_id(service, None).await? else {
            failures.push(format!("{service}=missing"));
            continue;
        };
        let state = compose.container_state(&id).await?;
        let fields: Vec<_> = state.split('|').collect();
        if fields.first() != Some(&"running")
            || fields.get(1) != Some(&"0")
            || !matches!(fields.get(2), Some(&"none") | Some(&"healthy"))
        {
            failures.push(format!("{service}={state}"));
        }
    }
    let Some(id) = compose.service_id("chain-preflight", None).await? else {
        failures.push("chain-preflight=missing".to_owned());
        return Ok(failures);
    };
    let state = compose.container_state(&id).await?;
    let fields: Vec<_> = state.split('|').collect();
    if fields.first() != Some(&"exited") || fields.get(1) != Some(&"0") {
        failures.push(format!("chain-preflight={state}"));
    }
    Ok(failures)
}

async fn endpoint_failures(config: &RuntimeConfig) -> Vec<String> {
    let domain = match config.required("SANDBOX_DOMAIN") {
        Ok(value) => value,
        Err(_) => return vec!["sandbox domain missing".to_owned()],
    };
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .redirect(reqwest::redirect::Policy::limited(5))
        .build()
    {
        Ok(value) => value,
        Err(error) => return vec![error.to_string()],
    };
    let mut failures = Vec::new();
    for (label, url, accepted) in [
        (
            "user application",
            format!("https://app.{domain}/"),
            200..400,
        ),
        (
            "administration application",
            format!("https://admin.{domain}/"),
            200..400,
        ),
        (
            "Block Explorer",
            format!("https://explorer.{domain}/"),
            200..400,
        ),
        (
            "Block Explorer API",
            format!("https://explorer-api.{domain}/"),
            100..500,
        ),
        (
            "Prividium API health",
            format!("https://api.{domain}/health"),
            200..300,
        ),
    ] {
        match client.get(url).send().await {
            Ok(response) if accepted.contains(&response.status().as_u16()) => {}
            Ok(response) => failures.push(format!("{label}=HTTP {}", response.status())),
            Err(_) => failures.push(format!("{label}=unreachable")),
        }
    }
    match client
        .post(format!("https://api.{domain}/rpc"))
        .json(&serde_json::json!({"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}))
        .send()
        .await
    {
        Ok(response) if matches!(response.status().as_u16(), 401 | 403) => {}
        Ok(response) => failures.push(format!("protected RPC denial=HTTP {}", response.status())),
        Err(_) => failures.push("protected RPC denial=unreachable".to_owned()),
    }
    let issuer = format!("https://idp.{domain}/realms/prividium");
    match client
        .get(format!("{issuer}/.well-known/openid-configuration"))
        .send()
        .await
    {
        Ok(response) => match response.json::<Value>().await {
            Ok(document)
                if document.get("issuer").and_then(Value::as_str) == Some(issuer.as_str()) => {}
            _ => failures.push("OIDC discovery issuer mismatch".to_owned()),
        },
        Err(_) => failures.push("OIDC discovery unavailable".to_owned()),
    }
    failures
}

fn write_incomplete_summary(
    context: &Context,
    config: &RuntimeConfig,
    failure: &str,
) -> Result<()> {
    let report = format!(
        "# Incomplete Prividium sandbox deployment\n\n- Generated: `{}`\n- Sandbox domain: `{}`\n- L2 chain ID: `{}`\n- Status: **INCOMPLETE**\n\n## Failed check\n\n- [ ] {}\n\nInspect `docker compose -f compose/compose.yaml --env-file /etc/prividium/runtime/sandbox.env ps --all` and logs, resolve the failure, then rerun `prividiumcli deploy`.\n\nThis protected diagnostic contains no private keys, passwords, or provider URLs.\n",
        Utc::now().format("%Y-%m-%dT%H:%M:%SZ"),
        config.required("SANDBOX_DOMAIN")?,
        config.l2_chain_id()?,
        failure,
    );
    atomic_write(
        &context
            .runtime_dir
            .join("reports/deployment-summary.incomplete.md"),
        0o600,
        report.as_bytes(),
        true,
    )
}

fn deployment_summary(context: &Context, config: &RuntimeConfig) -> Result<String> {
    let manifest: Value = serde_json::from_slice(
        &fs::read(context.public("manifest.json"))
            .map_err(|error| AppError::failed("PUBLIC_MANIFEST_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("PUBLIC_MANIFEST_INVALID", error.to_string()))?;
    let versions: Value = serde_yaml::from_slice(
        &fs::read(context.repo_root.join("deployment/versions.lock.yaml"))
            .map_err(|error| AppError::failed("VERSION_LOCK_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("VERSION_LOCK_INVALID", error.to_string()))?;
    let domain = config.required("SANDBOX_DOMAIN")?;
    let component = |name: &str, field: &str| {
        versions
            .pointer(&format!("/products/{name}/{field}"))
            .and_then(Value::as_str)
            .unwrap_or("unknown")
    };
    let address = |pointer: &str| {
        manifest
            .pointer(pointer)
            .and_then(Value::as_str)
            .unwrap_or("missing")
    };
    Ok(format!(
        "# Prividium sandbox deployment summary\n\n- Generated: `{}`\n- Status: **HEALTHY**\n- Ethereum settlement network: Sepolia (`11155111`)\n- L2 chain ID: `{}`\n- Chain name: `{}`\n- Base token and protocol fee asset: **ETH**\n- Data availability: **Stage-0 Validium (NoDA)**\n\n## Public interfaces\n\n| Interface | URL |\n| --- | --- |\n| User application | https://app.{domain} |\n| Administration | https://admin.{domain} |\n| Protected API and RPC | https://api.{domain} |\n| Block Explorer | https://explorer.{domain} |\n| Block Explorer API | https://explorer-api.{domain} |\n| OIDC issuer | https://idp.{domain}/realms/prividium |\n\n## Release\n\n| Component | Version | Locked source |\n| --- | --- | --- |\n| Protocol | {} | `{}` |\n| ZKsync OS server | {} | `{}` |\n| zk-deployer | {} | `{}` |\n| Prividium | {} | `{}` |\n| Block Explorer | {} | `{}` |\n\n## Enabled capabilities\n\n| Capability | State |\n| --- | --- |\n| Core Prividium, Explorer, identity, chain, and monitoring | Enabled |\n| SSO / EntryPoint / bundler | Unsupported — disabled |\n| Webhooks | Unsupported — disabled |\n| Institutional demo | Unsupported — disabled |\n\n## On-chain identity\n\n| Contract | Address |\n| --- | --- |\n| Bridgehub | `{}` |\n| Chain Type Manager | `{}` |\n| Testnet verifier | `{}` |\n| Chain diamond | `{}` |\n| Chain admin | `{}` |\n| Prividium transaction filterer | `{}` |\n\n## Automated checks\n\n- [x] The 14 core Compose services are running and chain-preflight completed successfully\n- [x] Public HTTPS interfaces and strict OIDC discovery are ready\n- [x] Unauthenticated protected RPC access is denied\n\n## Sandbox limitations\n\n- Single VPS with no high availability.\n- Fake proofs with a testnet verifier; no production proof security.\n- SOPS-managed hot keys; not a production custody design.\n- Do not use this sandbox to secure assets of value.\n",
        Utc::now().format("%Y-%m-%dT%H:%M:%SZ"),
        config.l2_chain_id()?,
        config.required("CHAIN_NAME")?,
        component("protocol", "version"),
        component("protocol", "source_commit"),
        component("zksync_os_server", "version"),
        component("zksync_os_server", "source_commit"),
        component("zk_deployer", "version"),
        component("zk_deployer", "source_commit"),
        component("prividium", "version"),
        component("prividium", "source_commit"),
        component("block_explorer", "version"),
        component("block_explorer", "source_commit"),
        address("/l1_contracts/bridgehub"),
        address("/l1_contracts/chain_type_manager"),
        address("/l1_contracts/testnet_verifier"),
        address("/chain_contracts/diamond"),
        address("/chain_contracts/chain_admin"),
        address("/transaction_filterer/address"),
    ))
}

async fn unresolved_dns(domain: &str) -> Vec<String> {
    let mut unresolved = Vec::new();
    for label in ["app", "admin", "api", "explorer", "explorer-api", "idp"] {
        let hostname = format!("{label}.{domain}");
        let target = format!("{hostname}:443");
        let resolved = tokio::task::spawn_blocking(move || {
            target
                .to_socket_addrs()
                .is_ok_and(|mut addresses| addresses.next().is_some())
        })
        .await
        .unwrap_or(false);
        if !resolved {
            unresolved.push(hostname);
        }
    }
    unresolved
}

fn pass(id: &str, message: &str) -> Check {
    Check {
        id: id.to_owned(),
        status: CheckStatus::Pass,
        message: message.to_owned(),
    }
}
