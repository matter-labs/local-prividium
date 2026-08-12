use std::{env, fs};

use chrono::Utc;
use serde_json::Value;

use crate::{
    artifacts::PublicManifest,
    cli::ProfileArgs,
    compose::Compose,
    config::validate_profile,
    context::Context,
    error::{AppError, Result},
    fs::atomic_write,
    output::{Artifact, Check, CheckStatus, CommandOutcome, Reporter},
    roles::RoleSet,
    runtime::{load_runtime, sha256_file},
};

pub async fn run(
    context: &Context,
    reporter: &Reporter,
    args: ProfileArgs,
) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    let config = load_runtime(context)?;
    let chain_id = config.l2_chain_id()?;
    let public_manifest = context.public("manifest.json");
    if public_manifest.is_file() {
        let manifest = load_manifest(&public_manifest)?;
        if manifest.l1_chain_id == 11_155_111 && manifest.l2_chain_id == chain_id {
            return Ok(CommandOutcome::complete(
                "broadcast",
                format!("Protocol broadcast is already complete for L2 chain {chain_id}."),
            )
            .next("prividiumcli deploy", false));
        }
        return Err(AppError::failed(
            "PUBLIC_MANIFEST_CONFLICT",
            "existing public manifest belongs to a different deployment",
        ));
    }
    let attempt_path = context.runtime_dir.join("reports/broadcast-attempt.json");
    if attempt_path.exists() {
        let attempt: Value =
            serde_json::from_slice(&fs::read(&attempt_path).map_err(|error| {
                AppError::review("BROADCAST_REVIEW_REQUIRED", error.to_string())
            })?)
            .map_err(|error| AppError::review("BROADCAST_REVIEW_REQUIRED", error.to_string()))?;
        if attempt.get("schema_version").and_then(Value::as_u64) != Some(1)
            || attempt.get("l2_chain_id").and_then(Value::as_u64) != Some(chain_id)
        {
            return Err(AppError::review(
                "BROADCAST_REVIEW_REQUIRED",
                "broadcast attempt evidence is invalid; preserve runtime state",
            ));
        }
        return Err(AppError::review(
            "BROADCAST_REVIEW_REQUIRED",
            "an approved broadcast previously started without producing the public manifest; do not rerun or discard /etc/prividium/runtime/chain",
        ));
    }

    reporter.progress("Running focused pre-broadcast readiness...");
    let prepared_image =
        crate::commands::prepare::prepared_readiness(context, reporter, &config, true).await?;
    let prepared_manifest = context.runtime_dir.join("chain/out/manifest.json");
    let preparation_path = context.runtime_dir.join("chain/out/preparation.json");
    let preparation: Value = serde_json::from_slice(
        &fs::read(&preparation_path)
            .map_err(|error| AppError::failed("PREPARATION_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("PREPARATION_INVALID", error.to_string()))?;
    let prepared_at = preparation
        .get("generated_at")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let manifest_digest = sha256_file(&prepared_manifest)?;
    let roles = RoleSet::from_runtime(&config)?;
    let deployer = roles.address("l1_deployer")?;
    let expected_confirmation = format!("BROADCAST_SEPOLIA_{chain_id}");
    reporter.progress(format!(
        "Broadcast authorization\nNetwork: Ethereum Sepolia (11155111)\nSandbox domain: {}\nL2 chain ID: {chain_id}\nEcosystem deployer: {deployer}\nPrepared at: {prepared_at}\nPrepared manifest: {manifest_digest}\nThis creates irreversible protocol contracts on Sepolia.",
        config.required("SANDBOX_DOMAIN")?
    ));
    if env::var("CONFIRM_BROADCAST").as_deref() != Ok(expected_confirmation.as_str()) {
        if !reporter.stdin_is_terminal() {
            return Err(AppError::action(
                "BROADCAST_CONFIRMATION_REQUIRED",
                format!(
                    "non-interactive execution requires CONFIRM_BROADCAST={expected_confirmation}"
                ),
                Some(format!(
                    "CONFIRM_BROADCAST={expected_confirmation} prividiumcli broadcast"
                )),
            ));
        }
        let typed = reporter
            .prompt("Type the L2 chain ID to broadcast: ")
            .map_err(|error| AppError::failed("PROMPT_FAILED", error.to_string()))?;
        if typed != chain_id.to_string() {
            return Err(AppError::action(
                "BROADCAST_CANCELLED",
                "broadcast cancelled; no protocol transactions were submitted",
                Some("prividiumcli broadcast"),
            ));
        }
    }

    let attempt = serde_json::to_vec_pretty(&serde_json::json!({
        "schema_version": 1,
        "status": "STARTED",
        "started_at": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "l1_chain_id": 11155111,
        "l2_chain_id": chain_id,
        "prepared_manifest_sha256": manifest_digest,
        "chain_bootstrap_image_id": prepared_image,
    }))
    .map_err(|error| AppError::failed("BROADCAST_ATTEMPT_WRITE_FAILED", error.to_string()))?;
    atomic_write(&attempt_path, 0o600, &attempt, false)?;

    reporter.progress("Broadcasting the prepared protocol deployment...");
    let compose = Compose::new(context, context.runtime_environment());
    if let Err(error) = compose
        .chain_bootstrap("broadcast", &config, reporter, Some(&expected_confirmation))
        .await
    {
        return Err(AppError::review(
            "BROADCAST_REVIEW_REQUIRED",
            format!(
                "a Sepolia transaction may have been submitted. Preserve runtime chain state and terminal output; do not retry automatically. Cause: {error}"
            ),
        ));
    }
    let manifest = load_manifest(&public_manifest).map_err(|error| {
        AppError::review(
            "BROADCAST_REVIEW_REQUIRED",
            format!("broadcast returned without valid public evidence: {error}"),
        )
    })?;
    if manifest.l1_chain_id != 11_155_111
        || manifest.l2_chain_id != chain_id
        || manifest.data_availability.mode != "no_da"
        || manifest.data_availability.kind != "validium"
        || !manifest.transaction_filterer.deposits_allowed
    {
        return Err(AppError::review(
            "BROADCAST_REVIEW_REQUIRED",
            "public manifest does not evidence the expected Validium/filterer deployment",
        ));
    }
    let mut completed: Value = serde_json::from_slice(&attempt)
        .map_err(|error| AppError::failed("BROADCAST_ATTEMPT_WRITE_FAILED", error.to_string()))?;
    completed["status"] = Value::String("COMPLETE".to_owned());
    completed["completed_at"] = Value::String(Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string());
    completed["public_manifest_sha256"] = Value::String(sha256_file(&public_manifest)?);
    atomic_write(
        &attempt_path,
        0o600,
        &serde_json::to_vec_pretty(&completed).map_err(|error| {
            AppError::failed("BROADCAST_ATTEMPT_WRITE_FAILED", error.to_string())
        })?,
        true,
    )?;

    let mut outcome = CommandOutcome::complete(
        "broadcast",
        "Protocol broadcast complete. Validium and the Prividium transaction filterer are deployed.",
    )
    .next("prividiumcli deploy", false);
    outcome.checks = vec![
        pass(
            "broadcast",
            "prepared protocol deployment broadcast completed",
        ),
        pass("validium", "data availability mode is no_da Validium"),
        pass(
            "transaction_filterer",
            "filterer is deployed and normal deposits are enabled",
        ),
    ];
    outcome.artifacts.push(Artifact {
        kind: "public_manifest".to_owned(),
        path: "deployment/public/manifest.json".to_owned(),
    });
    outcome.data = Some(serde_json::json!({
        "l1_chain_id": 11155111,
        "l2_chain_id": chain_id,
        "chain_bootstrap_image_id": prepared_image,
    }));
    Ok(outcome)
}

fn load_manifest(path: &std::path::Path) -> Result<PublicManifest> {
    serde_json::from_slice(
        &fs::read(path)
            .map_err(|error| AppError::failed("PUBLIC_MANIFEST_MISSING", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("PUBLIC_MANIFEST_INVALID", error.to_string()))
}

fn pass(id: &str, message: &str) -> Check {
    Check {
        id: id.to_owned(),
        status: CheckStatus::Pass,
        message: message.to_owned(),
    }
}
