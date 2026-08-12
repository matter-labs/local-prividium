use std::{env, fs, time::Duration};

use chrono::Utc;
use serde_json::{Value, json};
use tokio::time::{Instant, sleep};

use crate::{
    cli::ProfileArgs,
    compose::Compose,
    config::validate_profile,
    context::Context,
    error::{AppError, Result},
    fs::atomic_write,
    oidc::ProductSession,
    output::{Artifact, Check, CheckStatus, CommandOutcome, Reporter},
    roles::RoleSet,
    runtime::load_runtime,
};

pub async fn run(
    context: &Context,
    reporter: &Reporter,
    args: ProfileArgs,
) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    let config = load_runtime(context)?;
    let chain_id = config.l2_chain_id()?;
    validate_deployed_state(context, chain_id)?;
    let evidence_path = context.public("happy-path.json");
    let protected_evidence_path = context.runtime_dir.join("reports/happy-path.json");
    if let (Some(evidence), Some(protected)) = (
        load_json(&evidence_path),
        load_json(&protected_evidence_path),
    ) && evidence == protected
        && ready_evidence(&evidence, chain_id)
    {
        let mut outcome = CommandOutcome::complete(
            "verify",
            "Prividium happy path is already READY. No canary was repeated.",
        );
        outcome.stage = Some("READY".to_owned());
        outcome.data = Some(evidence);
        return Ok(outcome);
    }

    let started_at = Utc::now();
    let started = Instant::now();
    reporter.progress("[1/4] Authenticating a non-admin OIDC user and checking protected RPC");
    let session = ProductSession::login(&config).await?;
    reporter.progress("Non-admin OIDC login and authenticated eth_chainId succeeded");

    let roles = RoleSet::from_runtime(&config)?;
    let canary_address = roles.address("bridge_sponsor")?.to_owned();
    let attempt_path = context.runtime_dir.join("chain/canary-attempt.json");
    let submission_path = context.runtime_dir.join("chain/canary-submission.json");
    let launch_path = context.runtime_dir.join("reports/canary-attempt.json");
    let existing_submission = load_json(&submission_path)
        .filter(|value| valid_submission(value, chain_id, &canary_address));
    let expected_confirmation = format!("CANARY_SEPOLIA_{chain_id}");
    if existing_submission.is_some() {
        reporter
            .progress("Resuming the existing acceptance canary; no new submission is required.");
    } else {
        if attempt_path.exists() || launch_path.exists() {
            return Err(AppError::review(
                "CANARY_REVIEW_REQUIRED",
                "an approved canary was interrupted without durable submission evidence; inspect Sepolia before retrying",
            ));
        }
        reporter.progress(format!(
            "Canary authorization\nSender / recipient: {canary_address}\nL2 value: 0.000001 ETH\nPurpose: deposit, authenticated receipt, Explorer indexing\nThis submits an irreversible Sepolia testnet transaction."
        ));
        if env::var("CONFIRM_CANARY").as_deref() != Ok(expected_confirmation.as_str()) {
            if !reporter.stdin_is_terminal() {
                return Err(AppError::action(
                    "CANARY_CONFIRMATION_REQUIRED",
                    format!(
                        "non-interactive execution requires CONFIRM_CANARY={expected_confirmation}"
                    ),
                    Some(format!(
                        "CONFIRM_CANARY={expected_confirmation} prividiumcli verify"
                    )),
                ));
            }
            let typed = reporter
                .prompt("Type the L2 chain ID to submit the canary: ")
                .map_err(|error| AppError::failed("PROMPT_FAILED", error.to_string()))?;
            if typed != chain_id.to_string() {
                return Err(AppError::action(
                    "CANARY_CANCELLED",
                    "canary cancelled; no acceptance transaction was submitted",
                    Some("prividiumcli verify"),
                ));
            }
        }
        reporter.progress("[2/4] Submitting the minimal Sepolia-to-L2 canary");
        let launch = serde_json::to_vec_pretty(&json!({
            "schema_version": 1,
            "status": "STARTED",
            "started_at": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
            "l1_chain_id": 11155111,
            "l2_chain_id": chain_id,
            "canary_address": canary_address,
        }))
        .map_err(|error| AppError::failed("CANARY_ATTEMPT_WRITE_FAILED", error.to_string()))?;
        atomic_write(&launch_path, 0o600, &launch, false)?;
        let compose = Compose::new(context, context.runtime_environment());
        if let Err(error) = compose
            .canary(&config, reporter, &expected_confirmation)
            .await
        {
            return Err(AppError::review(
                "CANARY_REVIEW_REQUIRED",
                format!(
                    "the canary may have submitted a Sepolia transaction. Inspect the protected attempt and chain state before retrying. Cause: {error}"
                ),
            ));
        }
    }
    let submission = load_json(&submission_path).ok_or_else(|| {
        AppError::review(
            "CANARY_REVIEW_REQUIRED",
            "canary completed without durable submission evidence",
        )
    })?;
    if !valid_submission(&submission, chain_id, &canary_address) {
        return Err(AppError::review(
            "CANARY_REVIEW_REQUIRED",
            "canary submission evidence is invalid",
        ));
    }
    let l1_hash = submission
        .get("l1_transaction_hash")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let l2_hash = submission
        .get("l2_transaction_hash")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let completed_launch = serde_json::to_vec_pretty(&json!({
        "schema_version": 1,
        "status": "COMPLETE",
        "completed_at": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "l1_chain_id": 11155111,
        "l2_chain_id": chain_id,
        "canary_address": canary_address,
        "l1_transaction_hash": l1_hash,
        "l2_transaction_hash": l2_hash,
    }))
    .map_err(|error| AppError::failed("CANARY_ATTEMPT_WRITE_FAILED", error.to_string()))?;
    atomic_write(&launch_path, 0o600, &completed_launch, true)?;
    reporter.progress(format!(
        "Sepolia transaction: {l1_hash}\nL2 transaction: {l2_hash}"
    ));

    reporter.progress("[3/4] Waiting for the authenticated L2 receipt");
    wait_for_receipt(&session, &l2_hash, reporter).await?;
    reporter.progress("[4/4] Waiting for Block Explorer indexing");
    wait_for_explorer(context, &l2_hash, reporter).await?;

    let evidence = json!({
        "schema_version": 1,
        "status": "READY",
        "generated_at": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "qualification_started_at": started_at.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "elapsed_seconds": started.elapsed().as_secs(),
        "l1_chain_id": 11155111,
        "l2_chain_id": chain_id,
        "authenticated_rpc": true,
        "non_admin_oidc": true,
        "canary_receipt": true,
        "canary_address": canary_address,
        "l1_transaction_hash": l1_hash,
        "l2_transaction_hash": l2_hash,
        "explorer_indexed": true,
    });
    let bytes = serde_json::to_vec_pretty(&evidence)
        .map_err(|error| AppError::failed("HAPPY_PATH_EVIDENCE_WRITE_FAILED", error.to_string()))?;
    atomic_write(&protected_evidence_path, 0o600, &bytes, true)?;
    atomic_write(&evidence_path, 0o644, &bytes, true)?;

    let mut outcome = CommandOutcome::complete(
        "verify",
        "READY: authenticated product flow, canary receipt, and Explorer indexing succeeded.",
    );
    outcome.stage = Some("READY".to_owned());
    outcome.checks = vec![
        pass(
            "authenticated_rpc",
            "non-admin OIDC user called authenticated eth_chainId",
        ),
        pass(
            "canary_receipt",
            "minimal deposit has a successful authenticated L2 receipt",
        ),
        pass(
            "explorer_indexed",
            "Explorer indexed the canary transaction",
        ),
    ];
    outcome.artifacts.push(Artifact {
        kind: "happy_path_evidence".to_owned(),
        path: "deployment/public/happy-path.json".to_owned(),
    });
    outcome.data = Some(evidence);
    Ok(outcome)
}

fn validate_deployed_state(context: &Context, chain_id: u64) -> Result<()> {
    let manifest = load_json(&context.public("manifest.json")).ok_or_else(|| {
        AppError::action(
            "BROADCAST_REQUIRED",
            "matching Validium/filterer manifest is missing",
            Some("prividiumcli broadcast"),
        )
    })?;
    if manifest.get("l2_chain_id").and_then(Value::as_u64) != Some(chain_id)
        || manifest
            .pointer("/data_availability/mode")
            .and_then(Value::as_str)
            != Some("no_da")
        || manifest
            .pointer("/data_availability/type")
            .and_then(Value::as_str)
            != Some("validium")
        || manifest
            .pointer("/transaction_filterer/deposits_allowed")
            .and_then(Value::as_bool)
            != Some(true)
    {
        return Err(AppError::failed(
            "PUBLIC_MANIFEST_MISMATCH",
            "public manifest does not match the expected Validium/filterer deployment",
        ));
    }
    let summary = fs::read_to_string(context.public("deployment-summary.md")).map_err(|_| {
        AppError::action(
            "HEALTHY_DEPLOYMENT_REQUIRED",
            "healthy core deployment summary is missing",
            Some("prividiumcli deploy"),
        )
    })?;
    if !summary.contains("- Status: **HEALTHY**") {
        return Err(AppError::action(
            "HEALTHY_DEPLOYMENT_REQUIRED",
            "core deployment is not healthy",
            Some("prividiumcli deploy"),
        ));
    }
    Ok(())
}

async fn wait_for_receipt(
    session: &ProductSession,
    transaction_hash: &str,
    reporter: &Reporter,
) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(600);
    let mut next_report = Instant::now();
    loop {
        let receipt = session
            .rpc("eth_getTransactionReceipt", json!([transaction_hash]))
            .await?;
        if !receipt.is_null() {
            if receipt.get("status").and_then(Value::as_str) == Some("0x1") {
                return Ok(());
            }
            return Err(AppError::failed(
                "CANARY_RECEIPT_FAILED",
                "canary L2 receipt reports failure",
            ));
        }
        if Instant::now() >= deadline {
            return Err(AppError::failed(
                "CANARY_RECEIPT_TIMEOUT",
                "timed out waiting for the authenticated canary L2 receipt",
            ));
        }
        if Instant::now() >= next_report {
            reporter.progress("Waiting for the authenticated canary receipt...");
            next_report = Instant::now() + Duration::from_secs(30);
        }
        sleep(Duration::from_secs(10)).await;
    }
}

async fn wait_for_explorer(
    context: &Context,
    transaction_hash: &str,
    reporter: &Reporter,
) -> Result<()> {
    let compose = Compose::new(context, context.runtime_environment());
    let deadline = Instant::now() + Duration::from_secs(600);
    loop {
        let result = compose
            .exec_postgres(&format!(
                "SELECT EXISTS (SELECT 1 FROM \"transactions\" WHERE lower(\"hash\") = lower('{transaction_hash}'));"
            ))
            .await
            .unwrap_or_default();
        if result == "t" {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(AppError::failed(
                "EXPLORER_INDEX_TIMEOUT",
                "Explorer did not index the canary within 10 minutes",
            ));
        }
        reporter.progress(format!(
            "Waiting for Explorer to index {transaction_hash}..."
        ));
        sleep(Duration::from_secs(15)).await;
    }
}

fn load_json(path: &std::path::Path) -> Option<Value> {
    serde_json::from_slice(&fs::read(path).ok()?).ok()
}

fn valid_submission(value: &Value, chain_id: u64, address: &str) -> bool {
    value.get("l1_chain_id").and_then(Value::as_u64) == Some(11_155_111)
        && value.get("l2_chain_id").and_then(Value::as_u64) == Some(chain_id)
        && value
            .get("canary_address")
            .and_then(Value::as_str)
            .is_some_and(|value| value.eq_ignore_ascii_case(address))
        && value
            .get("l1_transaction_hash")
            .and_then(Value::as_str)
            .is_some_and(is_hash)
        && value
            .get("l2_transaction_hash")
            .and_then(Value::as_str)
            .is_some_and(is_hash)
}

fn ready_evidence(value: &Value, chain_id: u64) -> bool {
    value.get("schema_version").and_then(Value::as_u64) == Some(1)
        && value.get("status").and_then(Value::as_str) == Some("READY")
        && value.get("l1_chain_id").and_then(Value::as_u64) == Some(11_155_111)
        && value.get("l2_chain_id").and_then(Value::as_u64) == Some(chain_id)
        && value.get("authenticated_rpc").and_then(Value::as_bool) == Some(true)
        && value.get("non_admin_oidc").and_then(Value::as_bool) == Some(true)
        && value.get("canary_receipt").and_then(Value::as_bool) == Some(true)
        && value
            .get("canary_address")
            .and_then(Value::as_str)
            .is_some_and(|value| is_fixed_hex(value, 40))
        && value
            .get("l1_transaction_hash")
            .and_then(Value::as_str)
            .is_some_and(is_hash)
        && value
            .get("l2_transaction_hash")
            .and_then(Value::as_str)
            .is_some_and(is_hash)
        && value.get("explorer_indexed").and_then(Value::as_bool) == Some(true)
}

fn is_hash(value: &str) -> bool {
    is_fixed_hex(value, 64)
}

fn is_fixed_hex(value: &str, digits: usize) -> bool {
    value.strip_prefix("0x").is_some_and(|value| {
        value.len() == digits && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

fn pass(id: &str, message: &str) -> Check {
    Check {
        id: id.to_owned(),
        status: CheckStatus::Pass,
        message: message.to_owned(),
    }
}
