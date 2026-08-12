use std::{
    env, fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::Utc;
use rand::{Rng, rngs::OsRng};
use secrecy::{ExposeSecret, SecretString};
use serde_json::Value;
use zeroize::Zeroizing;

use crate::{
    cli::InitArgs,
    config::{InputConfig, MAX_L2_CHAIN_ID, MIN_L2_CHAIN_ID, RuntimeConfig, validate_profile},
    context::Context,
    error::{AppError, Result},
    fs::atomic_write,
    output::{Artifact, CommandOutcome, Reporter},
    process::{CommandSpec, require_commands},
    roles::{RoleSet, role_report},
    runtime::decrypt_runtime,
};

pub async fn run(context: &Context, reporter: &Reporter, args: InitArgs) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    let encrypted = context.encrypted_environment();
    if encrypted.exists()
        || encrypted
            .symlink_metadata()
            .is_ok_and(|value| value.file_type().is_symlink())
    {
        return Err(AppError::failed(
            "CONFIGURATION_EXISTS",
            format!(
                "{} already exists; initialization will not replace it",
                encrypted.display()
            ),
        ));
    }
    require_commands("sandbox initialization", &["age-keygen", "sops", "cast"])?;

    let input_path = resolve_input_path(context, &args.env_file);
    let input = InputConfig::load(&input_path)?;
    reporter.progress(format!(
        "Initializing sandbox configuration from {} (values hidden)",
        input_path.display()
    ));

    let age_key = ensure_age_identity(context, reporter).await?;
    let recipient = derive_recipient(&age_key).await?;
    if let Ok(expected) = env::var("SOPS_AGE_RECIPIENT")
        && expected != recipient
    {
        return Err(AppError::failed(
            "AGE_RECIPIENT_MISMATCH",
            "SOPS_AGE_RECIPIENT does not match SOPS_AGE_KEY_FILE",
        ));
    }

    let chain_id = match input.l2_chain_id {
        Some(value) => value,
        None => generate_chain_id().await?,
    };
    let signer = generate_funding_signer().await?;
    let roles = RoleSet::generate_with(
        "bridge_sponsor",
        Some(SecretString::from(signer.private_key.to_string())),
    )?;
    let admin_password = random_hex(16);
    let user_1_password = random_hex(16);
    let user_2_password = random_hex(16);
    let plaintext = Zeroizing::new(render_secret_environment(
        &input,
        chain_id,
        &roles,
        &signer,
        &admin_password,
        &user_1_password,
        &user_2_password,
    )?);
    let expected_config = RuntimeConfig::parse(&plaintext)?;
    let encrypted_bytes = CommandSpec::new("sops")
        .args([
            "--age",
            recipient.as_str(),
            "--input-type",
            "dotenv",
            "--output-type",
            "dotenv",
            "--encrypt",
            "/dev/stdin",
        ])
        .env("SOPS_AGE_KEY_FILE", age_key.as_os_str())
        .stdin(plaintext.as_bytes().to_vec())
        .checked("SOPS encryption")
        .await?;
    if encrypted_bytes.is_empty() {
        return Err(AppError::failed(
            "SOPS_ENCRYPTION_FAILED",
            "SOPS returned an empty encrypted configuration",
        ));
    }

    let report = role_report(&input.domain, chain_id, &roles)?;
    atomic_write(&encrypted, 0o600, &encrypted_bytes, false)?;
    if let Err(error) = atomic_write(&context.public("roles.md"), 0o644, report.as_bytes(), true) {
        let _ = fs::remove_file(&encrypted);
        return Err(error);
    }
    let verified_config = decrypt_runtime(context).await?;
    if !expected_config.iter().eq(verified_config.iter()) {
        return Err(AppError::failed(
            "ENCRYPTED_CONFIGURATION_MISMATCH",
            "the encrypted configuration did not decrypt to the generated values; retain the plaintext input and inspect the protected outputs",
        ));
    }
    let removed_default_input = input_path == context.repo_root.join("deployment/input.env");
    if removed_default_input {
        fs::remove_file(&input_path).map_err(|error| {
            AppError::failed(
                "PLAINTEXT_INPUT_REMOVE_FAILED",
                format!(
                    "encrypted outputs are verified, but {} could not be removed: {error}",
                    input_path.display()
                ),
            )
        })?;
    }

    reporter.progress(format!("Generated L2 chain ID: {chain_id}"));
    let mut outcome = CommandOutcome::complete(
        "init",
        "Initialization complete. Generated passwords remain encrypted and were not printed.",
    )
    .next("prividiumcli fund", false);
    outcome.artifacts = vec![
        Artifact {
            kind: "encrypted_configuration".to_owned(),
            path: "deployment/secrets/sandbox.enc.env".to_owned(),
        },
        Artifact {
            kind: "role_inventory".to_owned(),
            path: "deployment/public/roles.md".to_owned(),
        },
    ];
    outcome.data = Some(serde_json::json!({
        "profile": "sandbox",
        "l1_chain_id": 11155111,
        "l2_chain_id": chain_id,
        "initialized_at": Utc::now(),
        "plaintext_input_removed": removed_default_input,
    }));
    if !removed_default_input {
        outcome.warnings.push(format!(
            "the explicitly selected input remains at {}; remove it after verifying the encrypted outputs",
            input_path.display()
        ));
    }
    Ok(outcome)
}

struct FundingSigner {
    private_key: Zeroizing<String>,
    keystore_b64: Zeroizing<String>,
    password: Zeroizing<String>,
}

async fn generate_funding_signer() -> Result<FundingSigner> {
    let directory = tempfile::tempdir()
        .map_err(|error| AppError::failed("SIGNER_DIRECTORY_FAILED", error.to_string()))?;
    fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o700))
        .map_err(|error| AppError::failed("SIGNER_DIRECTORY_FAILED", error.to_string()))?;
    let password = Zeroizing::new(random_hex(32));
    let output = CommandSpec::new("cast")
        .args(["wallet", "new"])
        .arg(directory.path())
        .arg("sponsor")
        .env("CAST_PASSWORD", password.as_str())
        .output("funding-wallet generation")
        .await?;
    if !output.status.success() {
        return Err(AppError::failed(
            "SIGNER_GENERATION_FAILED",
            "cast could not generate the encrypted funding-wallet signer",
        ));
    }
    let keystore = directory.path().join("sponsor");
    let keystore_bytes = fs::read(&keystore)
        .map_err(|error| AppError::failed("SIGNER_GENERATION_FAILED", error.to_string()))?;
    let decrypted = CommandSpec::new("cast")
        .args(["wallet", "decrypt-keystore", "sponsor", "--keystore-dir"])
        .arg(directory.path())
        .env("CAST_UNSAFE_PASSWORD", password.as_str())
        .checked("funding-wallet verification")
        .await?;
    let decrypted = Zeroizing::new(String::from_utf8_lossy(&decrypted).into_owned());
    let private_key = decrypted
        .split_whitespace()
        .find(|word| is_private_key(word))
        .ok_or_else(|| {
            AppError::failed(
                "SIGNER_GENERATION_FAILED",
                "cast did not return the generated funding-wallet key",
            )
        })?;
    Ok(FundingSigner {
        private_key: Zeroizing::new(private_key.to_owned()),
        keystore_b64: Zeroizing::new(STANDARD.encode(keystore_bytes)),
        password,
    })
}

async fn ensure_age_identity(context: &Context, reporter: &Reporter) -> Result<PathBuf> {
    if let Some(path) = env::var_os("SOPS_AGE_KEY_FILE").map(PathBuf::from) {
        crate::fs::ensure_regular_file(&path, None)?;
        return Ok(path);
    }
    let path = context.age_key();
    if path.exists() {
        crate::fs::ensure_regular_file(&path, Some(0o600))?;
        reporter.progress("Reusing local Age identity");
        return Ok(path);
    }
    let parent = path.parent().ok_or_else(|| {
        AppError::failed(
            "AGE_IDENTITY_PATH_INVALID",
            "Age identity path has no parent",
        )
    })?;
    fs::create_dir_all(parent)
        .map_err(|error| AppError::failed("AGE_IDENTITY_CREATE_FAILED", error.to_string()))?;
    let output = CommandSpec::new("age-keygen")
        .args(["-o"])
        .arg(&path)
        .output("Age identity generation")
        .await?;
    if !output.status.success() {
        let _ = fs::remove_file(&path);
        return Err(AppError::failed(
            "AGE_IDENTITY_CREATE_FAILED",
            "age-keygen could not create the local identity",
        ));
    }
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
        .map_err(|error| AppError::failed("AGE_IDENTITY_CREATE_FAILED", error.to_string()))?;
    reporter.progress("Created local Age identity");
    Ok(path)
}

async fn derive_recipient(age_key: &Path) -> Result<String> {
    let output = CommandSpec::new("age-keygen")
        .arg("-y")
        .arg(age_key)
        .checked("Age recipient derivation")
        .await?;
    let recipient = String::from_utf8_lossy(&output).trim().to_owned();
    if recipient.is_empty() || recipient.contains('\n') {
        return Err(AppError::failed(
            "AGE_IDENTITY_INVALID",
            "Age identity must contain exactly one identity",
        ));
    }
    Ok(recipient)
}

async fn generate_chain_id() -> Result<u64> {
    let chains: Value = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .map_err(|error| AppError::failed("HTTP_CLIENT_FAILED", error.to_string()))?
        .get("https://chainid.network/chains.json")
        .send()
        .await
        .and_then(reqwest::Response::error_for_status)
        .map_err(|error| {
            AppError::action(
                "CHAINLIST_UNAVAILABLE",
                format!("could not check Chainlist before generating an L2 chain ID: {error}"),
                Some("prividiumcli init"),
            )
        })?
        .json()
        .await
        .map_err(|error| AppError::failed("CHAINLIST_INVALID", error.to_string()))?;
    let used: std::collections::BTreeSet<u64> = chains
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|chain| chain.get("chainId")?.as_u64())
        .collect();
    for _ in 0..100 {
        let candidate = OsRng.gen_range(MIN_L2_CHAIN_ID..=MAX_L2_CHAIN_ID);
        if !used.contains(&candidate) {
            return Ok(candidate);
        }
    }
    Err(AppError::failed(
        "CHAIN_ID_GENERATION_FAILED",
        "could not generate an unused high-range L2 chain ID",
    ))
}

fn render_secret_environment(
    input: &InputConfig,
    chain_id: u64,
    roles: &RoleSet,
    signer: &FundingSigner,
    admin_password: &str,
    user_1_password: &str,
    user_2_password: &str,
) -> Result<String> {
    let mut values: Vec<(String, String)> = vec![
        ("SANDBOX_DOMAIN".into(), input.domain.clone()),
        ("ACME_EMAIL".into(), input.acme_email.clone()),
        ("SANDBOX_ADMIN_EMAIL".into(), "admin@local.dev".into()),
        ("CHAIN_NAME".into(), "Prividium Sandbox".into()),
        ("L2_CHAIN_ID".into(), chain_id.to_string()),
        ("L1_CHAIN_ID".into(), "11155111".into()),
        ("ETH_PRICE_USD".into(), "3000".into()),
        ("RUNTIME_DIR".into(), "/etc/prividium/runtime".into()),
        (
            "SEPOLIA_RPC_URL".into(),
            input.sepolia_rpc_url.expose_secret().to_owned(),
        ),
        (
            "SEPOLIA_BROWSER_RPC_URL".into(),
            input.sepolia_browser_rpc_url.clone(),
        ),
    ];
    values.extend(
        roles
            .secret_pairs()
            .map(|(name, value)| (name.to_owned(), value.to_owned())),
    );
    values.extend([
        (
            "AUTH_SERVER_ADMIN_ADDRESS".into(),
            roles.address("auth_server_admin")?.to_owned(),
        ),
        (
            "OPERATOR_MIN_L1_BALANCE_WEI".into(),
            "10000000000000000".into(),
        ),
        (
            "DEPLOYMENT_SIGNER_MIN_L1_BALANCE_WEI".into(),
            "10000000000000000".into(),
        ),
        (
            "BRIDGE_SPONSOR_KEYSTORE_B64".into(),
            signer.keystore_b64.to_string(),
        ),
        (
            "BRIDGE_SPONSOR_KEYSTORE_PASSWORD".into(),
            signer.password.to_string(),
        ),
        ("BUNDLER_ENABLED".into(), "false".into()),
        ("SERVICE_WALLET_TARGET_L2_ETH".into(), "0.05".into()),
        ("FACTORY_DEPLOYER_FUNDING_ETH".into(), "0.012".into()),
        ("POSTGRES_SUPERUSER_PASSWORD".into(), random_hex(24)),
        ("PRIVIDIUM_DB_NAME".into(), "prividium_api".into()),
        ("PRIVIDIUM_DB_USER".into(), "prividium".into()),
        ("PRIVIDIUM_DB_PASSWORD".into(), random_hex(24)),
        ("EXPLORER_DB_NAME".into(), "prividium_block_explorer".into()),
        ("EXPLORER_DB_USER".into(), "explorer".into()),
        ("EXPLORER_DB_PASSWORD".into(), random_hex(24)),
        ("KEYCLOAK_DB_NAME".into(), "keycloak".into()),
        ("KEYCLOAK_DB_USER".into(), "keycloak".into()),
        ("KEYCLOAK_DB_PASSWORD".into(), random_hex(24)),
        ("WEBHOOK_DB_NAME".into(), "zksync_webhook_db".into()),
        ("WEBHOOK_DB_USER".into(), "webhook".into()),
        ("WEBHOOK_DB_PASSWORD".into(), random_hex(24)),
        (
            "KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME".into(),
            format!("kcadmin-{}", random_hex(4)),
        ),
        ("KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD".into(), random_hex(24)),
        ("SANDBOX_ADMIN_PASSWORD".into(), admin_password.into()),
        ("SANDBOX_USER_1_EMAIL".into(), "user1@local.dev".into()),
        ("SANDBOX_USER_1_PASSWORD".into(), user_1_password.into()),
        ("SANDBOX_USER_2_EMAIL".into(), "user2@local.dev".into()),
        ("SANDBOX_USER_2_PASSWORD".into(), user_2_password.into()),
        ("SIWE_HMAC_SECRET".into(), random_hex(32)),
        ("EXPLORER_SESSION_SECRET".into(), random_hex(32)),
        ("WEBHOOK_ENCRYPTION_KEY".into(), random_hex(32)),
        ("WEBHOOK_ENCRYPTION_KDF_SALT".into(), random_hex(24)),
        (
            "WEBHOOK_PRIVIDIUM_API_KEY".into(),
            format!("priv_sk_{}", random_hex(32)),
        ),
        ("WEBHOOK_ENABLED".into(), "false".into()),
        ("GRAFANA_ADMIN_USER".into(), "sandbox-admin".into()),
        ("GRAFANA_ADMIN_PASSWORD".into(), random_hex(24)),
        ("REOWN_PROJECT_ID".into(), String::new()),
        (
            "DEMO_USER_1_EMAIL".into(),
            format!("demo-admin@{}", input.domain),
        ),
        ("DEMO_USER_1_PASSWORD".into(), random_hex(24)),
        (
            "DEMO_USER_2_EMAIL".into(),
            format!("demo-member@{}", input.domain),
        ),
        ("DEMO_USER_2_PASSWORD".into(), random_hex(24)),
    ]);
    let mut document = String::new();
    for (name, value) in values {
        if value.contains(['\n', '\r', '\0', '"']) {
            return Err(AppError::failed(
                "UNSAFE_GENERATED_VALUE",
                format!("generated {name} cannot be represented safely"),
            ));
        }
        document.push_str(&name);
        document.push('=');
        document.push('"');
        document.push_str(&value);
        document.push_str("\"\n");
    }
    Ok(document)
}

fn resolve_input_path(context: &Context, configured: &Path) -> PathBuf {
    if configured == Path::new("deployment/input.env") {
        context.repo_root.join(configured)
    } else {
        configured.to_path_buf()
    }
}

fn random_hex(bytes: usize) -> String {
    let mut value = vec![0_u8; bytes];
    OsRng.fill(&mut value[..]);
    hex::encode(value)
}

fn is_private_key(value: &str) -> bool {
    value.strip_prefix("0x").is_some_and(|value| {
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}
