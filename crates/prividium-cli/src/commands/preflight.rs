use std::{fs, io::Write, net::ToSocketAddrs, os::unix::fs::PermissionsExt, time::Duration};

use reqwest::header::{
    ACCESS_CONTROL_ALLOW_HEADERS, ACCESS_CONTROL_ALLOW_METHODS, ACCESS_CONTROL_ALLOW_ORIGIN,
    ACCESS_CONTROL_REQUEST_HEADERS, ACCESS_CONTROL_REQUEST_METHOD, ORIGIN,
};
use serde_json::{Value, json};

use crate::{
    cli::{FundingScope, ProfileArgs},
    compose::Compose,
    config::{RuntimeConfig, validate_profile},
    context::Context,
    error::{AppError, Result},
    output::{Check, CheckStatus, CommandOutcome, Reporter},
    process::{CommandSpec, require_commands},
    roles::{RoleSet, address_from_private_key},
    rpc::{EthereumRpc, quantity_u64},
    runtime::{decrypt_runtime, ensure_encrypted_environment},
};

pub async fn run(
    context: &Context,
    reporter: &Reporter,
    args: ProfileArgs,
) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    ensure_encrypted_environment(context)?;
    require_commands(
        "sandbox preflight",
        &["age", "age-keygen", "cast", "docker", "sops"],
    )?;
    if std::env::consts::OS != "linux" || std::env::consts::ARCH != "x86_64" {
        return Err(AppError::failed(
            "DEPLOYMENT_HOST_REQUIRED",
            "sandbox deployment requires Linux amd64; see runbooks/HOST_CONTRACT.md",
        ));
    }
    crate::fs::ensure_private_directory(&context.runtime_dir)?;
    if context.public("manifest.json").exists() {
        return Err(AppError::failed(
            "PROTOCOL_ALREADY_BROADCAST",
            "a public protocol manifest already exists; use deploy for this sandbox",
        ));
    }
    let config = decrypt_runtime(context).await?;
    validate_required_configuration(&config)?;
    let roles = RoleSet::from_runtime(&config)?;
    validate_role_inventory(context, &config, &roles)?;
    validate_private_rpc(&config).await?;
    validate_browser_rpc(&config).await?;
    validate_chain_id_collision(&config).await?;
    validate_docker(context, &config).await?;
    validate_private_images(context).await?;
    crate::commands::fund::reconcile(context, reporter, FundingScope::All, true).await?;

    let unresolved = unresolved_dns(config.required("SANDBOX_DOMAIN")?).await;
    let mut outcome = CommandOutcome::complete(
        "preflight",
        "Preflight passed. No transactions were submitted and no persistent configuration was changed.",
    )
    .next("prividiumcli prepare", false);
    outcome.checks = vec![
        pass(
            "configuration",
            "encrypted configuration and generated identities are valid",
        ),
        pass(
            "runtime",
            "Linux amd64, protected runtime, Docker, and Compose v2 are available",
        ),
        pass(
            "private_rpc",
            "private RPC is Sepolia and supports deployment capabilities",
        ),
        pass(
            "browser_rpc",
            "browser RPC is Sepolia and allows the sandbox origin",
        ),
        pass(
            "chain_id",
            "L2 chain ID is high-range and absent from Chainlist",
        ),
        pass(
            "private_images",
            "pull-only credentials can access the pinned Prividium images",
        ),
        pass(
            "funding",
            "six protocol roles and the canary reserve are funded",
        ),
    ];
    if !unresolved.is_empty() {
        outcome.warnings.push(format!(
            "DNS is not yet resolved for {}; complete it before deploy",
            unresolved.join(", ")
        ));
        outcome.checks.push(Check {
            id: "dns".to_owned(),
            status: CheckStatus::Warning,
            message: "DNS is nonblocking until deployment".to_owned(),
        });
    } else {
        outcome
            .checks
            .push(pass("dns", "all six core hostnames resolve"));
    }
    outcome.data = Some(json!({
        "profile": "sandbox",
        "l1_chain_id": 11155111,
        "l2_chain_id": config.l2_chain_id()?,
        "dns_unresolved": unresolved,
        "mutated": false,
        "transactions_submitted": false,
    }));
    Ok(outcome)
}

fn validate_required_configuration(config: &RuntimeConfig) -> Result<()> {
    for name in [
        "SANDBOX_DOMAIN",
        "ACME_EMAIL",
        "L2_CHAIN_ID",
        "RUNTIME_DIR",
        "SEPOLIA_RPC_URL",
        "SEPOLIA_BROWSER_RPC_URL",
        "BRIDGE_SPONSOR_KEYSTORE_B64",
        "BRIDGE_SPONSOR_KEYSTORE_PASSWORD",
        "AUTH_SERVER_ADMIN_PRIVATE_KEY",
        "AUTH_SERVER_ADMIN_ADDRESS",
    ] {
        config.required(name)?;
    }
    if config.required("SEPOLIA_RPC_URL")?.trim_end_matches('/')
        == config
            .required("SEPOLIA_BROWSER_RPC_URL")?
            .trim_end_matches('/')
    {
        return Err(AppError::failed(
            "RPC_URLS_NOT_DISTINCT",
            "private and browser RPC URLs must be separate",
        ));
    }
    Ok(())
}

fn validate_role_inventory(
    context: &Context,
    config: &RuntimeConfig,
    roles: &RoleSet,
) -> Result<()> {
    let configured = config.required("AUTH_SERVER_ADMIN_ADDRESS")?;
    let derived = address_from_private_key(config.required("AUTH_SERVER_ADMIN_PRIVATE_KEY")?)?;
    if !configured.eq_ignore_ascii_case(&derived) {
        return Err(AppError::failed(
            "AUTH_ADMIN_ADDRESS_MISMATCH",
            "AUTH_SERVER_ADMIN_ADDRESS does not match its private key",
        ));
    }
    let report = fs::read_to_string(context.public("roles.md")).map_err(|_| {
        AppError::failed("ROLE_INVENTORY_MISSING", "public role inventory is missing")
    })?;
    let fingerprint = report
        .lines()
        .find_map(|line| {
            line.strip_prefix("- Role-set fingerprint: `")?
                .split('`')
                .next()
        })
        .unwrap_or_default();
    if fingerprint != roles.fingerprint() {
        return Err(AppError::failed(
            "ROLE_INVENTORY_MISMATCH",
            "public role inventory does not match the encrypted identity set",
        ));
    }
    Ok(())
}

async fn validate_private_rpc(config: &RuntimeConfig) -> Result<()> {
    let rpc = EthereumRpc::new(
        config.required("SEPOLIA_RPC_URL")?.to_owned(),
        Duration::from_secs(15),
    )?;
    let chain_id = quantity_u64(&rpc.call("eth_chainId", json!([])).await?, "L1 chain ID")?;
    if chain_id != 11_155_111 {
        return Err(AppError::failed(
            "WRONG_L1_NETWORK",
            format!("private RPC returned chain ID {chain_id}; expected Sepolia"),
        ));
    }
    let latest = quantity_u64(
        &rpc.call("eth_blockNumber", json!([])).await?,
        "latest block",
    )?;
    if latest < 64 {
        return Err(AppError::failed(
            "RPC_CAPABILITY_MISSING",
            "Sepolia RPC is unexpectedly below block 64",
        ));
    }
    let historical = format!("0x{:x}", latest - 64);
    let block = rpc
        .call("eth_getBlockByNumber", json!([historical, false]))
        .await?;
    if block
        .get("number")
        .and_then(Value::as_str)
        .map(str::to_ascii_lowercase)
        != Some(historical.to_ascii_lowercase())
        || !block.get("transactions").is_some_and(Value::is_array)
    {
        return Err(AppError::failed(
            "RPC_CAPABILITY_MISSING",
            "private RPC does not provide historical blocks",
        ));
    }
    let historical_call = rpc
        .call(
            "eth_call",
            json!([{"to":"0x0000000000000000000000000000000000000000","data":"0x"}, historical]),
        )
        .await?;
    if historical_call.as_str() != Some("0x") {
        return Err(AppError::failed(
            "RPC_CAPABILITY_MISSING",
            "private RPC does not support historical eth_call",
        ));
    }
    if !rpc
        .call(
            "eth_getLogs",
            json!([{"fromBlock":historical,"toBlock":historical}]),
        )
        .await?
        .is_array()
    {
        return Err(AppError::failed(
            "RPC_CAPABILITY_MISSING",
            "private RPC does not support historical log queries",
        ));
    }
    let mut transaction = None;
    for offset in 0..=8 {
        let number = if offset == 0 {
            "latest".to_owned()
        } else {
            format!("0x{:x}", latest - offset)
        };
        let block = rpc
            .call("eth_getBlockByNumber", json!([number, false]))
            .await?;
        transaction = block
            .get("transactions")
            .and_then(Value::as_array)
            .and_then(|values| values.first())
            .and_then(Value::as_str)
            .map(str::to_owned);
        if transaction.is_some() {
            break;
        }
    }
    let transaction = transaction.ok_or_else(|| {
        AppError::failed(
            "RPC_CAPABILITY_MISSING",
            "no recent transaction was available for receipt validation",
        )
    })?;
    let receipt = rpc
        .call("eth_getTransactionReceipt", json!([transaction]))
        .await?;
    if receipt
        .get("transactionHash")
        .and_then(Value::as_str)
        .is_none_or(|value| !value.eq_ignore_ascii_case(&transaction))
        || receipt.get("blockNumber").is_none_or(Value::is_null)
    {
        return Err(AppError::failed(
            "RPC_CAPABILITY_MISSING",
            "private RPC does not provide transaction receipts",
        ));
    }
    quantity_u64(
        &rpc.call("eth_blobBaseFee", json!([])).await?,
        "blob base fee",
    )?;
    Ok(())
}

async fn validate_browser_rpc(config: &RuntimeConfig) -> Result<()> {
    let domain = config.required("SANDBOX_DOMAIN")?;
    let origin = format!("https://app.{domain}");
    let url = config.required("SEPOLIA_BROWSER_RPC_URL")?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|error| AppError::failed("HTTP_CLIENT_FAILED", error.to_string()))?;
    let options = client
        .request(reqwest::Method::OPTIONS, url)
        .header(ORIGIN, &origin)
        .header(ACCESS_CONTROL_REQUEST_METHOD, "POST")
        .header(ACCESS_CONTROL_REQUEST_HEADERS, "content-type")
        .send()
        .await
        .map_err(|error| {
            AppError::action(
                "BROWSER_RPC_CORS_REQUIRED",
                format!("browser RPC OPTIONS request failed: {error}"),
                Some("prividiumcli preflight"),
            )
        })?;
    let allowed_origin = options
        .headers()
        .get(ACCESS_CONTROL_ALLOW_ORIGIN)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let allowed_methods = options
        .headers()
        .get(ACCESS_CONTROL_ALLOW_METHODS)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let allowed_headers = options
        .headers()
        .get(ACCESS_CONTROL_ALLOW_HEADERS)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    if !matches_token(allowed_origin, &origin)
        || !matches_token(allowed_methods, "post")
        || !matches_token(allowed_headers, "content-type")
    {
        return Err(AppError::action(
            "BROWSER_RPC_CORS_REQUIRED",
            format!("browser RPC must allow origin {origin}, method POST, and header content-type"),
            Some("prividiumcli preflight"),
        ));
    }
    let rpc = EthereumRpc::new(url.to_owned(), Duration::from_secs(15))?;
    let (result, headers) = rpc
        .call_with_origin("eth_chainId", json!([]), &origin)
        .await?;
    if quantity_u64(&result, "browser RPC chain ID")? != 11_155_111 {
        return Err(AppError::failed(
            "WRONG_BROWSER_RPC_NETWORK",
            "browser RPC is not Ethereum Sepolia",
        ));
    }
    let post_origin = headers
        .get(ACCESS_CONTROL_ALLOW_ORIGIN)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    if !matches_token(post_origin, &origin) {
        return Err(AppError::action(
            "BROWSER_RPC_CORS_REQUIRED",
            format!("browser RPC POST must allow origin {origin}"),
            Some("prividiumcli preflight"),
        ));
    }
    Ok(())
}

async fn validate_chain_id_collision(config: &RuntimeConfig) -> Result<()> {
    let chain_id = config.l2_chain_id()?;
    let chains: Value = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| AppError::failed("HTTP_CLIENT_FAILED", error.to_string()))?
        .get("https://chainid.network/chains.json")
        .send()
        .await
        .and_then(reqwest::Response::error_for_status)
        .map_err(|error| {
            AppError::action(
                "CHAINLIST_UNAVAILABLE",
                format!("Chainlist collision check failed: {error}"),
                Some("prividiumcli preflight"),
            )
        })?
        .json()
        .await
        .map_err(|error| AppError::failed("CHAINLIST_INVALID", error.to_string()))?;
    if chains
        .as_array()
        .into_iter()
        .flatten()
        .any(|entry| entry.get("chainId").and_then(Value::as_u64) == Some(chain_id))
    {
        return Err(AppError::failed(
            "L2_CHAIN_ID_COLLISION",
            format!("L2 chain ID {chain_id} is already listed in Chainlist"),
        ));
    }
    Ok(())
}

async fn validate_docker(context: &Context, config: &RuntimeConfig) -> Result<()> {
    let info = CommandSpec::new("docker")
        .arg("info")
        .output("Docker daemon inspection")
        .await?;
    if !info.status.success() {
        return Err(AppError::failed(
            "DOCKER_UNAVAILABLE",
            "Docker daemon is not reachable by the current user; satisfy the documented host prerequisites",
        ));
    }
    let compose = CommandSpec::new("docker")
        .args(["compose", "version"])
        .output("Docker Compose inspection")
        .await?;
    if !compose.status.success() {
        return Err(AppError::failed(
            "DOCKER_COMPOSE_UNAVAILABLE",
            "Docker Compose v2 is unavailable; satisfy the documented host prerequisites",
        ));
    }
    let mut environment = tempfile::NamedTempFile::new()
        .map_err(|error| AppError::failed("TEMPORARY_FILE_FAILED", error.to_string()))?;
    environment
        .as_file_mut()
        .set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|error| AppError::failed("TEMPORARY_FILE_FAILED", error.to_string()))?;
    for (name, value) in config.iter() {
        writeln!(environment, "{name}=\"{value}\"")
            .map_err(|error| AppError::failed("TEMPORARY_FILE_FAILED", error.to_string()))?;
    }
    Compose::new(context, environment.path()).validate().await
}

async fn validate_private_images(context: &Context) -> Result<()> {
    let versions: Value = serde_yaml::from_slice(
        &fs::read(context.repo_root.join("deployment/versions.lock.yaml"))
            .map_err(|error| AppError::failed("VERSION_LOCK_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("VERSION_LOCK_INVALID", error.to_string()))?;
    let images = versions
        .pointer("/products/prividium/images")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            AppError::failed("VERSION_LOCK_INVALID", "Prividium image locks are missing")
        })?;
    for name in ["permissions_api", "user_panel", "admin_panel"] {
        let image = images.get(name).and_then(Value::as_str).ok_or_else(|| {
            AppError::failed(
                "VERSION_LOCK_INVALID",
                format!("private image lock {name} is missing"),
            )
        })?;
        let output = CommandSpec::new("docker")
            .args(["manifest", "inspect", image])
            .output("private image access")
            .await?;
        if !output.status.success() {
            return Err(AppError::action(
                "QUAY_AUTHENTICATION_REQUIRED",
                format!("pull-only credentials cannot access pinned image {name}"),
                Some("docker login quay.io && prividiumcli preflight"),
            ));
        }
    }
    Ok(())
}

async fn unresolved_dns(domain: &str) -> Vec<String> {
    let mut unresolved = Vec::new();
    for label in ["app", "admin", "api", "explorer", "explorer-api", "idp"] {
        let hostname = format!("{label}.{domain}");
        let target = format!("{hostname}:443");
        let resolves = tokio::task::spawn_blocking(move || {
            target
                .to_socket_addrs()
                .is_ok_and(|mut values| values.next().is_some())
        })
        .await
        .unwrap_or(false);
        if !resolves {
            unresolved.push(hostname);
        }
    }
    unresolved
}

fn matches_token(header: &str, expected: &str) -> bool {
    header == "*"
        || header
            .split(',')
            .map(str::trim)
            .any(|value| value.eq_ignore_ascii_case(expected))
}

fn pass(id: &str, message: &str) -> Check {
    Check {
        id: id.to_owned(),
        status: CheckStatus::Pass,
        message: message.to_owned(),
    }
}
