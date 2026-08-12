use std::{fs, os::unix::fs::PermissionsExt, time::Instant};

use serde_json::Value;

use crate::{
    cli::{FundingScope, ProfileArgs},
    compose::{Compose, ensure_nonempty_regular},
    config::{RuntimeConfig, validate_profile},
    context::Context,
    error::{AppError, Result},
    output::{Artifact, Check, CheckStatus, CommandOutcome, Reporter},
    process::{CommandSpec, require_commands},
    runtime::{load_runtime, materialize_runtime, sha256_file},
};

const PROTOCOL_COMMIT: &str = "e091691063c99a1d0281d6fe42fb0ec4430f3673";
const DEPLOYER_COMMIT: &str = "16c6a83b4f634609958f347c56549ba19bf9df9b";

pub async fn run(
    context: &Context,
    reporter: &Reporter,
    args: ProfileArgs,
) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    if context.public("manifest.json").exists() {
        return Err(AppError::failed(
            "PROTOCOL_ALREADY_BROADCAST",
            "a public protocol manifest already exists; use deploy for this sandbox",
        ));
    }
    require_commands("sandbox preparation", &["cast", "docker", "sops"])?;
    crate::fs::ensure_private_directory(&context.runtime_dir)?;
    let started = Instant::now();
    reporter.progress("[1/5] Creating the protected runtime");
    let config = materialize_runtime(context).await?;
    let chain_dir = context.runtime_dir.join("chain");
    fs::create_dir_all(&chain_dir)
        .map_err(|error| AppError::failed("CHAIN_DIRECTORY_CREATE_FAILED", error.to_string()))?;
    fs::set_permissions(&chain_dir, fs::Permissions::from_mode(0o700))
        .map_err(|error| AppError::failed("CHAIN_DIRECTORY_CREATE_FAILED", error.to_string()))?;

    let compose = Compose::new(context, context.runtime_environment());
    reporter.progress("[2/5] Building and simulating the protocol deployment");
    let prepared_image = compose
        .chain_bootstrap("prepare", &config, reporter, None)
        .await?;
    for (name, path) in [
        (
            "prepared manifest",
            context.runtime_dir.join("chain/out/manifest.json"),
        ),
        (
            "preparation provenance",
            context.runtime_dir.join("chain/out/preparation.json"),
        ),
    ] {
        ensure_nonempty_regular(&path, name)?;
    }

    reporter.progress("[3/5] Pulling digest-pinned stack images");
    compose.pull_locked().await?;
    reporter.progress("[4/5] Building the local operator-balance-exporter helper");
    compose.build_operator_exporter().await?;
    reporter.progress("[5/5] Checking focused pre-broadcast readiness");
    prepared_readiness(context, reporter, &config, true).await?;

    let mut outcome = CommandOutcome::complete(
        "prepare",
        "Preparation complete. No Sepolia transactions were submitted.",
    )
    .next("prividiumcli broadcast", true);
    outcome.checks = vec![
        pass(
            "runtime",
            "protected runtime environment created with mode 0600",
        ),
        pass(
            "protocol_simulation",
            "Validium ecosystem and transaction filterer simulation completed",
        ),
        pass(
            "prepared_image",
            "the exact chain-bootstrap image identity was recorded",
        ),
        pass(
            "images",
            "digest-pinned images were pulled and local helpers built",
        ),
        pass("readiness", "pre-broadcast readiness passed"),
    ];
    outcome.artifacts = vec![
        Artifact {
            kind: "runtime_environment".to_owned(),
            path: "/etc/prividium/runtime/sandbox.env".to_owned(),
        },
        Artifact {
            kind: "prepared_manifest".to_owned(),
            path: "/etc/prividium/runtime/chain/out/manifest.json".to_owned(),
        },
        Artifact {
            kind: "preparation_provenance".to_owned(),
            path: "/etc/prividium/runtime/chain/out/preparation.json".to_owned(),
        },
    ];
    outcome.data = Some(serde_json::json!({
        "l1_chain_id": 11155111,
        "l2_chain_id": config.l2_chain_id()?,
        "chain_bootstrap_image_id": prepared_image,
        "elapsed_seconds": started.elapsed().as_secs(),
        "transactions_submitted": false,
    }));
    Ok(outcome)
}

pub async fn prepared_readiness(
    context: &Context,
    reporter: &Reporter,
    config: &RuntimeConfig,
    require_images: bool,
) -> Result<String> {
    let runtime = load_runtime(context)?;
    let expected: Vec<_> = config.iter().collect();
    let actual: Vec<_> = runtime.iter().collect();
    if expected != actual {
        return Err(AppError::failed(
            "RUNTIME_CONFIGURATION_STALE",
            "protected runtime differs from the encrypted configuration; rerun prepare",
        ));
    }
    let manifest_path = context.runtime_dir.join("chain/out/manifest.json");
    let state_path = context.runtime_dir.join("chain/state.json");
    let preparation_path = context.runtime_dir.join("chain/out/preparation.json");
    ensure_nonempty_regular(&manifest_path, "prepared manifest")?;
    ensure_nonempty_regular(&state_path, "prepared chain state")?;
    ensure_nonempty_regular(&preparation_path, "preparation provenance")?;
    let preparation: Value = serde_json::from_slice(
        &fs::read(&preparation_path)
            .map_err(|error| AppError::failed("PREPARATION_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("PREPARATION_INVALID", error.to_string()))?;
    let chain_id = config.l2_chain_id()?;
    let image = preparation
        .get("chain_bootstrap_image_id")
        .and_then(Value::as_str)
        .filter(|value| valid_image(value))
        .ok_or_else(|| {
            AppError::failed("PREPARATION_INVALID", "prepared image identity is missing")
        })?;
    let valid = preparation.get("schema_version").and_then(Value::as_u64) == Some(1)
        && preparation.get("l1_chain_id").and_then(Value::as_u64) == Some(11_155_111)
        && preparation.get("l2_chain_id").and_then(Value::as_u64) == Some(chain_id)
        && preparation
            .pointer("/sources/protocol")
            .and_then(Value::as_str)
            == Some(PROTOCOL_COMMIT)
        && preparation
            .pointer("/sources/zk_deployer")
            .and_then(Value::as_str)
            == Some(DEPLOYER_COMMIT)
        && preparation
            .get("data_availability_mode")
            .and_then(Value::as_str)
            == Some("no_da")
        && preparation
            .pointer("/transaction_filterer/enabled")
            .and_then(Value::as_bool)
            == Some(true)
        && preparation
            .pointer("/transaction_filterer/deposits_allowed")
            .and_then(Value::as_bool)
            == Some(true)
        && preparation
            .get("chain_state_sha256")
            .and_then(Value::as_str)
            == Some(&sha256_file(&state_path)?)
        && preparation
            .get("prepared_manifest_sha256")
            .and_then(Value::as_str)
            == Some(&sha256_file(&manifest_path)?);
    if !valid {
        return Err(AppError::failed(
            "PREPARATION_INVALID",
            "prepared protocol provenance is invalid or stale",
        ));
    }
    let versions = fs::read_to_string(context.repo_root.join("deployment/versions.lock.yaml"))
        .map_err(|error| AppError::failed("VERSION_LOCK_READ_FAILED", error.to_string()))?;
    if !versions.contains(PROTOCOL_COMMIT) || !versions.contains(DEPLOYER_COMMIT) {
        return Err(AppError::failed(
            "VERSION_LOCK_MISMATCH",
            "protocol or deployer source lock changed after preparation",
        ));
    }
    if context.public("manifest.json").exists() {
        return Err(AppError::failed(
            "PROTOCOL_ALREADY_BROADCAST",
            "public manifest already exists; do not broadcast again",
        ));
    }
    crate::commands::fund::reconcile(context, reporter, FundingScope::All, true).await?;
    let compose = Compose::new(context, context.runtime_environment());
    compose.validate().await?;
    let inspect = CommandSpec::new("docker")
        .args(["image", "inspect", image])
        .output("prepared image inspection")
        .await?;
    if !inspect.status.success() {
        return Err(AppError::failed(
            "PREPARED_IMAGE_MISSING",
            "the exact chain-bootstrap image used for simulation is unavailable",
        ));
    }
    if require_images {
        for image in compose.images(Some(image)).await? {
            let inspect = CommandSpec::new("docker")
                .args(["image", "inspect", image.as_str()])
                .output("prepared image inventory")
                .await?;
            if !inspect.status.success() {
                return Err(AppError::failed(
                    "PREPARED_STACK_IMAGE_MISSING",
                    format!("prepared stack image is missing: {image}"),
                ));
            }
        }
    }
    Ok(image.to_owned())
}

fn valid_image(value: &str) -> bool {
    value.strip_prefix("sha256:").is_some_and(|value| {
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

fn pass(id: &str, message: &str) -> Check {
    Check {
        id: id.to_owned(),
        status: CheckStatus::Pass,
        message: message.to_owned(),
    }
}
