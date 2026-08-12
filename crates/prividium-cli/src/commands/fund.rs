use std::{
    collections::BTreeMap, fs, os::unix::fs::PermissionsExt, path::PathBuf, str::FromStr,
    time::Duration,
};

use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::Utc;
use ruint::aliases::U256;
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use tokio::time::{Instant, sleep};

use crate::{
    cli::{FundArgs, FundingScope},
    config::{RuntimeConfig, validate_profile},
    context::Context,
    error::{AppError, ErrorKind, Result},
    fs::atomic_write,
    output::{Check, CheckStatus, CommandOutcome, Reporter},
    process::{CommandOutput, CommandSpec, require_commands},
    roles::{RoleSet, role},
    runtime::decrypt_runtime,
};

#[derive(Debug, Deserialize)]
struct FundingTargets {
    schema_version: u32,
    l1_chain_id: u64,
    canary_reserve_wei: String,
    targets_wei: BTreeMap<String, String>,
}

#[derive(Debug, Clone)]
struct FundingRow {
    role: &'static str,
    address: String,
    current: U256,
    target: U256,
    shortfall: U256,
}

#[derive(Debug)]
struct FundingPlan {
    rows: Vec<FundingRow>,
    sponsor_address: String,
    sponsor_balance: U256,
    canary_reserve: U256,
    total_shortfall: U256,
    gas_allowance: U256,
    required_balance: U256,
    latest_nonce: String,
    pending_nonce: String,
    id: String,
}

struct FundingLock {
    path: PathBuf,
}

impl Drop for FundingLock {
    fn drop(&mut self) {
        let _ = fs::remove_dir(&self.path);
    }
}

pub async fn run(context: &Context, reporter: &Reporter, args: FundArgs) -> Result<CommandOutcome> {
    validate_profile(&args.profile)?;
    if args.list {
        return list_roles();
    }
    reconcile(context, reporter, args.scope, false).await
}

pub async fn reconcile(
    context: &Context,
    reporter: &Reporter,
    scope: FundingScope,
    check_only: bool,
) -> Result<CommandOutcome> {
    if context.public("manifest.json").exists() {
        return Err(AppError::failed(
            "FUNDING_AFTER_BROADCAST",
            "initial role funding is pre-broadcast only",
        ));
    }
    require_commands("sandbox funding", &["cast"])?;
    crate::fs::ensure_private_directory(&context.runtime_dir)?;
    let config = decrypt_runtime(context).await?;
    let roles = RoleSet::from_runtime(&config)?;
    let targets = load_targets(context)?;
    validate_inventory(context, &roles)?;
    let lock_path = context.repo_root.join("deployment/secrets/.fund.lock");
    if check_only && lock_path.exists() {
        return Err(AppError::action(
            "FUNDING_IN_PROGRESS",
            "another funding command is already running",
            Some("prividiumcli preflight"),
        ));
    }
    let _lock = if check_only {
        None
    } else {
        fs::create_dir(&lock_path).map_err(|_| {
            AppError::action(
                "FUNDING_LOCKED",
                format!(
                    "another funding command is running; if it is stale, inspect and remove {}",
                    lock_path.display()
                ),
                Some("prividiumcli fund"),
            )
        })?;
        Some(FundingLock { path: lock_path })
    };
    let signer = prepare_signer(&config, &roles).await?;
    let selected = selected_roles(scope);
    let mut plan = load_plan(&config, &roles, &targets, selected, check_only).await?;
    print_plan(reporter, scope, &plan);

    if plan.latest_nonce != plan.pending_nonce {
        return Err(AppError::action(
            "FUNDING_TRANSACTION_PENDING",
            "the funding wallet has a pending Sepolia transaction",
            Some("prividiumcli fund"),
        ));
    }
    if plan.total_shortfall == U256::ZERO && plan.sponsor_balance >= plan.required_balance {
        if matches!(scope, FundingScope::All) && !check_only {
            write_funding_evidence(context, &config, &roles, &targets, plan.canary_reserve)?;
        }
        return Ok(funding_complete(scope, &plan, false));
    }
    if check_only {
        return Err(AppError::action(
            "FUNDING_REQUIRED",
            "one or more roles or the acceptance-canary reserve are below target",
            Some("prividiumcli fund"),
        ));
    }
    if plan.sponsor_balance < plan.required_balance {
        let missing = plan.required_balance - plan.sponsor_balance;
        let mut error = AppError::action(
            "FUNDING_WALLET_TOP_UP_REQUIRED",
            format!(
                "add at least {} Sepolia ETH to {}",
                format_eth(missing),
                plan.sponsor_address
            ),
            Some("prividiumcli fund"),
        );
        error.next_command = Some("prividiumcli fund".to_owned());
        return Err(error);
    }
    if !reporter.stdin_is_terminal() {
        return Err(AppError::action(
            "FUNDING_CONFIRMATION_REQUIRED",
            "funding transfers require an interactive terminal confirmation",
            Some("prividiumcli fund"),
        ));
    }
    let count = plan
        .rows
        .iter()
        .filter(|row| row.shortfall > U256::ZERO)
        .count();
    let answer = reporter
        .prompt(&format!(
            "Submit {count} irreversible Sepolia testnet transfer(s)? [y/N] "
        ))
        .map_err(|error| AppError::failed("PROMPT_FAILED", error.to_string()))?;
    if !matches!(answer.as_str(), "y" | "Y" | "yes" | "YES") {
        return Err(AppError::action(
            "FUNDING_CANCELLED",
            "funding declined; no transfers were submitted",
            Some("prividiumcli fund"),
        ));
    }

    let rechecked = load_plan(&config, &roles, &targets, selected, false).await?;
    if rechecked.id != plan.id {
        return Err(AppError::failed(
            "FUNDING_PLAN_CHANGED",
            "balances or nonce changed after confirmation; rerun to review the new plan",
        ));
    }
    plan = rechecked;
    let rpc = config.required("SEPOLIA_RPC_URL")?;
    let mut confirmed = 0_usize;
    for row in &plan.rows {
        if row.shortfall == U256::ZERO {
            continue;
        }
        let current = cast_u256(rpc, ["balance", row.address.as_str()]).await?;
        if current >= row.target {
            reporter.progress(format!("{} is already funded", role(row.role)?.label));
            continue;
        }
        let shortfall = row.target - current;
        reporter.progress(format!(
            "Funding {} with {} Sepolia ETH...",
            role(row.role)?.label,
            format_eth(shortfall)
        ));
        let output = cast(
            rpc,
            CommandSpec::new("cast")
                .arg("send")
                .arg(&row.address)
                .arg("--value")
                .arg(format!("{shortfall}wei"))
                .arg("--keystore")
                .arg(&signer.keystore)
                .arg("--password-file")
                .arg(&signer.password)
                .arg("--async"),
            "funding transfer",
        )
        .await;
        let output = match output {
            Ok(output) => output,
            Err(error) => return Err(manual_review(error, confirmed)),
        };
        let transaction_hash =
            extract_hash(&String::from_utf8_lossy(&output.stdout)).ok_or_else(|| {
                manual_review(
                    AppError::failed(
                        "FUNDING_TRANSACTION_HASH_MISSING",
                        "funding transfer returned no transaction hash",
                    ),
                    confirmed,
                )
            })?;
        reporter.progress(format!(
            "Submitted {transaction_hash}; waiting for confirmation..."
        ));
        if let Err(error) = wait_receipt(rpc, &transaction_hash).await {
            return Err(manual_review(error, confirmed));
        }
        let after = cast_u256(rpc, ["balance", row.address.as_str()]).await?;
        if after < row.target {
            return Err(manual_review(
                AppError::failed(
                    "FUNDING_TARGET_NOT_REACHED",
                    format!(
                        "{} remains below target after {transaction_hash}",
                        role(row.role)?.label
                    ),
                ),
                confirmed,
            ));
        }
        confirmed += 1;
    }

    let final_plan = load_plan(&config, &roles, &targets, selected, true).await?;
    if final_plan.total_shortfall != U256::ZERO
        || final_plan.sponsor_balance < final_plan.canary_reserve
    {
        return Err(manual_review(
            AppError::failed(
                "FUNDING_RECONCILIATION_FAILED",
                "funding completed but one or more requirements remain unsatisfied",
            ),
            confirmed,
        ));
    }
    if matches!(scope, FundingScope::All) {
        write_funding_evidence(
            context,
            &config,
            &roles,
            &targets,
            final_plan.canary_reserve,
        )?;
    }
    Ok(funding_complete(scope, &final_plan, true))
}

struct SignerFiles {
    _directory: tempfile::TempDir,
    keystore: PathBuf,
    password: PathBuf,
}

async fn prepare_signer(config: &RuntimeConfig, roles: &RoleSet) -> Result<SignerFiles> {
    let directory = tempfile::tempdir()
        .map_err(|error| AppError::failed("SIGNER_DIRECTORY_FAILED", error.to_string()))?;
    fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o700))
        .map_err(|error| AppError::failed("SIGNER_DIRECTORY_FAILED", error.to_string()))?;
    let keystore = directory.path().join("sponsor");
    let password = directory.path().join("password");
    let keystore_password = config.required("BRIDGE_SPONSOR_KEYSTORE_PASSWORD")?;
    let decoded = STANDARD
        .decode(config.required("BRIDGE_SPONSOR_KEYSTORE_B64")?)
        .map_err(|_| {
            AppError::failed(
                "FUNDING_KEYSTORE_INVALID",
                "funding-wallet keystore is invalid base64",
            )
        })?;
    fs::write(&keystore, decoded)
        .and_then(|_| fs::write(&password, format!("{keystore_password}\n")))
        .map_err(|error| AppError::failed("FUNDING_KEYSTORE_WRITE_FAILED", error.to_string()))?;
    fs::set_permissions(&keystore, fs::Permissions::from_mode(0o600))
        .and_then(|_| fs::set_permissions(&password, fs::Permissions::from_mode(0o600)))
        .map_err(|error| AppError::failed("FUNDING_KEYSTORE_WRITE_FAILED", error.to_string()))?;
    let output = CommandSpec::new("cast")
        .args(["wallet", "address", "--keystore"])
        .arg(&keystore)
        .arg("--password-file")
        .arg(&password)
        .output("funding-wallet verification")
        .await?;
    if !output.status.success()
        || !String::from_utf8_lossy(&output.stdout)
            .trim()
            .eq_ignore_ascii_case(roles.address("bridge_sponsor")?)
    {
        return Err(AppError::failed(
            "FUNDING_KEYSTORE_MISMATCH",
            "funding-wallet keystore does not match its configured identity",
        ));
    }
    Ok(SignerFiles {
        _directory: directory,
        keystore,
        password,
    })
}

async fn load_plan(
    config: &RuntimeConfig,
    roles: &RoleSet,
    targets: &FundingTargets,
    selected: &'static [&'static str],
    check_only: bool,
) -> Result<FundingPlan> {
    let rpc = config.required("SEPOLIA_RPC_URL")?;
    let chain_id = cast_text(
        rpc,
        CommandSpec::new("cast").arg("chain-id"),
        "Sepolia chain ID",
    )
    .await?;
    if chain_id.trim() != "11155111" {
        return Err(AppError::failed(
            "WRONG_L1_NETWORK",
            format!(
                "configured RPC returned chain ID {}; expected Sepolia",
                chain_id.trim()
            ),
        ));
    }
    let mut rows = Vec::new();
    let mut total_shortfall = U256::ZERO;
    for id in selected {
        let address = roles.address(id)?.to_owned();
        let current = cast_u256(rpc, ["balance", address.as_str()]).await?;
        let target = parse_u256(
            targets.targets_wei.get(*id).ok_or_else(|| {
                AppError::failed(
                    "FUNDING_TARGET_MISSING",
                    format!("funding target missing for {id}"),
                )
            })?,
            "funding target",
        )?;
        let shortfall = target.saturating_sub(current);
        total_shortfall += shortfall;
        rows.push(FundingRow {
            role: id,
            address,
            current,
            target,
            shortfall,
        });
    }
    let sponsor_address = roles.address("bridge_sponsor")?.to_owned();
    let sponsor_balance = cast_u256(rpc, ["balance", sponsor_address.as_str()]).await?;
    let latest_nonce = cast_text(
        rpc,
        CommandSpec::new("cast").args([
            "rpc",
            "eth_getTransactionCount",
            sponsor_address.as_str(),
            "latest",
        ]),
        "funding-wallet latest nonce",
    )
    .await?
    .trim_matches('"')
    .to_owned();
    let pending_nonce = cast_text(
        rpc,
        CommandSpec::new("cast").args([
            "rpc",
            "eth_getTransactionCount",
            sponsor_address.as_str(),
            "pending",
        ]),
        "funding-wallet pending nonce",
    )
    .await?
    .trim_matches('"')
    .to_owned();
    if !valid_quantity(&latest_nonce) || !valid_quantity(&pending_nonce) {
        return Err(AppError::failed(
            "FUNDING_NONCE_INVALID",
            "funding-wallet nonce response is invalid",
        ));
    }
    let canary_reserve = parse_u256(&targets.canary_reserve_wei, "canary reserve")?;
    let recipient_count = rows.iter().filter(|row| row.shortfall > U256::ZERO).count();
    let gas_allowance = if check_only {
        U256::ZERO
    } else {
        let gas_price = cast_u256(rpc, ["gas-price"]).await?;
        gas_price * U256::from(21_000_u64) * U256::from(recipient_count) * U256::from(2_u8)
    };
    let required_balance = total_shortfall + gas_allowance + canary_reserve;
    let mut canonical = format!(
        "l1_chain_id=11155111\nl2_chain_id={}\nsponsor={}\nsponsor_balance={sponsor_balance}\ncanary_reserve={canary_reserve}\ngas_allowance={gas_allowance}\nrequired_balance={required_balance}\nlatest_nonce={latest_nonce}\npending_nonce={pending_nonce}\n",
        config.l2_chain_id()?,
        sponsor_address.to_ascii_lowercase(),
    );
    for row in &rows {
        canonical.push_str(&format!(
            "{}\t{}\t{}\t{}\t{}\n",
            row.role, row.address, row.current, row.target, row.shortfall
        ));
    }
    let id = hex::encode(Sha256::digest(canonical.as_bytes()));
    Ok(FundingPlan {
        rows,
        sponsor_address,
        sponsor_balance,
        canary_reserve,
        total_shortfall,
        gas_allowance,
        required_balance,
        latest_nonce,
        pending_nonce,
        id,
    })
}

fn load_targets(context: &Context) -> Result<FundingTargets> {
    let path = context.repo_root.join("deployment/funding-targets.json");
    let targets: FundingTargets = serde_json::from_slice(
        &fs::read(&path)
            .map_err(|error| AppError::failed("FUNDING_TARGETS_READ_FAILED", error.to_string()))?,
    )
    .map_err(|error| AppError::failed("FUNDING_TARGETS_INVALID", error.to_string()))?;
    if targets.schema_version != 1 || targets.l1_chain_id != 11_155_111 {
        return Err(AppError::failed(
            "FUNDING_TARGETS_INVALID",
            "funding targets must use schema 1 and Ethereum Sepolia",
        ));
    }
    parse_u256(&targets.canary_reserve_wei, "canary reserve")?;
    for id in [
        "l1_deployer",
        "ecosystem_governor",
        "chain_owner",
        "operator_commit",
        "operator_prove",
        "operator_execute",
    ] {
        parse_u256(
            targets.targets_wei.get(id).ok_or_else(|| {
                AppError::failed(
                    "FUNDING_TARGET_MISSING",
                    format!("funding target missing for {id}"),
                )
            })?,
            "funding target",
        )?;
    }
    Ok(targets)
}

fn validate_inventory(context: &Context, roles: &RoleSet) -> Result<()> {
    let document = fs::read_to_string(context.public("roles.md")).map_err(|_| {
        AppError::failed(
            "ROLE_INVENTORY_MISSING",
            "public role inventory is missing; start from a fresh init identity set",
        )
    })?;
    let actual = document
        .lines()
        .find_map(|line| {
            line.strip_prefix("- Role-set fingerprint: `")?
                .split('`')
                .next()
        })
        .unwrap_or_default();
    if actual != roles.fingerprint() {
        return Err(AppError::failed(
            "ROLE_INVENTORY_MISMATCH",
            "public role inventory does not match the encrypted identities",
        ));
    }
    Ok(())
}

fn write_funding_evidence(
    context: &Context,
    config: &RuntimeConfig,
    roles: &RoleSet,
    targets: &FundingTargets,
    canary_reserve: U256,
) -> Result<()> {
    let targets_bytes = fs::read(context.repo_root.join("deployment/funding-targets.json"))
        .map_err(|error| AppError::failed("FUNDING_TARGETS_READ_FAILED", error.to_string()))?;
    let document = serde_json::to_vec_pretty(&serde_json::json!({
        "schema_version": 1,
        "status": "FUNDED",
        "generated_at": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "l1_chain_id": targets.l1_chain_id,
        "l2_chain_id": config.l2_chain_id()?,
        "role_set_fingerprint": roles.fingerprint(),
        "canary_reserve_wei": canary_reserve.to_string(),
        "funding_targets_sha256": hex::encode(Sha256::digest(targets_bytes)),
    }))
    .map_err(|error| AppError::failed("FUNDING_EVIDENCE_WRITE_FAILED", error.to_string()))?;
    atomic_write(
        &context.runtime_dir.join("reports/funding-ready.json"),
        0o600,
        &document,
        true,
    )
}

fn print_plan(reporter: &Reporter, scope: FundingScope, plan: &FundingPlan) {
    reporter.progress(format!(
        "Prividium sandbox funding\nNetwork: Ethereum Sepolia (11155111)\nScope: {}\nFunding wallet: {}\nConfirmed balance: {} ETH",
        scope_name(scope),
        plan.sponsor_address,
        format_eth(plan.sponsor_balance),
    ));
    for row in &plan.rows {
        reporter.progress(format!(
            "{} | {} | current {} | target {} | add {}",
            role(row.role).map_or(row.role, |role| role.label),
            row.address,
            format_eth(row.current),
            format_eth(row.target),
            format_eth(row.shortfall),
        ));
    }
    reporter.progress(format!(
        "Total to distribute: {} ETH\nEstimated distribution gas: {} ETH\nCanary reserve: {} ETH\nRequired wallet balance: {} ETH",
        format_eth(plan.total_shortfall),
        format_eth(plan.gas_allowance),
        format_eth(plan.canary_reserve),
        format_eth(plan.required_balance),
    ));
}

fn funding_complete(scope: FundingScope, plan: &FundingPlan, changed: bool) -> CommandOutcome {
    let mut outcome = CommandOutcome::complete(
        "fund",
        if changed {
            format!("Funding complete for {}.", scope_name(scope))
        } else {
            format!(
                "Funding requirements are already satisfied for {}.",
                scope_name(scope)
            )
        },
    );
    outcome.next_action = Some(crate::output::NextAction {
        command: if matches!(scope, FundingScope::All) {
            "prividiumcli preflight".to_owned()
        } else {
            "prividiumcli fund".to_owned()
        },
        requires_confirmation: false,
    });
    outcome.checks.push(Check {
        id: "funding.requirements".to_owned(),
        status: CheckStatus::Pass,
        message: "selected role targets and canary reserve are satisfied".to_owned(),
    });
    outcome.data = Some(serde_json::json!({
        "scope": scope_name(scope),
        "funding_wallet": plan.sponsor_address,
        "canary_reserve_wei": plan.canary_reserve.to_string(),
        "changed": changed,
    }));
    outcome
}

fn list_roles() -> Result<CommandOutcome> {
    let mut outcome = CommandOutcome::complete(
        "fund",
        "The customer funds only the sandbox funding wallet; the CLI distributes to the six required roles.",
    );
    outcome.data = Some(serde_json::json!({
        "groups": {
            "deployment": ["l1_deployer", "ecosystem_governor", "chain_owner"],
            "operators": ["operator_commit", "operator_prove", "operator_execute"]
        },
        "customer_funds": "bridge_sponsor"
    }));
    Ok(outcome)
}

async fn wait_receipt(rpc: &str, hash: &str) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(180);
    loop {
        let output = cast(
            rpc,
            CommandSpec::new("cast").args(["receipt", hash, "--async", "--json"]),
            "funding receipt",
        )
        .await?;
        if output.status.success()
            && let Ok(receipt) = serde_json::from_slice::<Value>(&output.stdout)
        {
            let receipt_hash = receipt
                .get("transactionHash")
                .or_else(|| receipt.get("transaction_hash"))
                .and_then(Value::as_str)
                .unwrap_or_default();
            let status = receipt
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if !receipt_hash.eq_ignore_ascii_case(hash) {
                return Err(AppError::failed(
                    "FUNDING_RECEIPT_MISMATCH",
                    "funding receipt returned the wrong transaction hash",
                ));
            }
            if matches!(status, "0x1" | "1") {
                return Ok(());
            }
            if matches!(status, "0x0" | "0") {
                return Err(AppError::failed(
                    "FUNDING_TRANSACTION_REVERTED",
                    format!("funding transaction reverted: {hash}"),
                ));
            }
        }
        if Instant::now() >= deadline {
            return Err(AppError::failed(
                "FUNDING_RECEIPT_TIMEOUT",
                format!("timed out waiting for funding transaction {hash}"),
            ));
        }
        sleep(Duration::from_secs(2)).await;
    }
}

async fn cast_u256<const N: usize>(rpc: &str, args: [&str; N]) -> Result<U256> {
    parse_u256(
        cast_text(rpc, CommandSpec::new("cast").args(args), "Sepolia RPC read")
            .await?
            .trim(),
        "Sepolia quantity",
    )
}

async fn cast_text(rpc: &str, command: CommandSpec, context: &'static str) -> Result<String> {
    let output = cast(rpc, command, context).await?;
    if !output.status.success() {
        return Err(AppError::action(
            "SEPOLIA_RPC_UNAVAILABLE",
            format!("{context} failed; retry after RPC connectivity is restored"),
            Some("prividiumcli fund"),
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

async fn cast(rpc: &str, command: CommandSpec, context: &'static str) -> Result<CommandOutput> {
    command
        .env("ETH_RPC_URL", rpc)
        .env("ETH_RPC_TIMEOUT", "15")
        .output(context)
        .await
}

fn parse_u256(value: &str, label: &str) -> Result<U256> {
    U256::from_str(value).map_err(|_| {
        AppError::failed(
            "INVALID_DECIMAL_QUANTITY",
            format!("{label} is not an unsigned decimal integer"),
        )
    })
}

fn valid_quantity(value: &str) -> bool {
    value.strip_prefix("0x").is_some_and(|value| {
        !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

fn extract_hash(value: &str) -> Option<String> {
    value.split_whitespace().find_map(|word| {
        let candidate =
            word.trim_matches(|character: char| !character.is_ascii_hexdigit() && character != 'x');
        candidate
            .strip_prefix("0x")
            .filter(|value| value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()))
            .map(|value| format!("0x{value}"))
    })
}

fn format_eth(value: U256) -> String {
    let digits = value.to_string();
    if digits.len() <= 18 {
        let fraction = format!("{:0>18}", digits).trim_end_matches('0').to_owned();
        if fraction.is_empty() {
            "0".to_owned()
        } else {
            format!("0.{fraction}")
        }
    } else {
        let split = digits.len() - 18;
        let fraction = digits[split..].trim_end_matches('0');
        if fraction.is_empty() {
            digits[..split].to_owned()
        } else {
            format!("{}.{}", &digits[..split], fraction)
        }
    }
}

fn selected_roles(scope: FundingScope) -> &'static [&'static str] {
    match scope {
        FundingScope::All => &[
            "l1_deployer",
            "ecosystem_governor",
            "chain_owner",
            "operator_commit",
            "operator_prove",
            "operator_execute",
        ],
        FundingScope::Deployment => &["l1_deployer", "ecosystem_governor", "chain_owner"],
        FundingScope::Operators => &["operator_commit", "operator_prove", "operator_execute"],
    }
}

fn scope_name(scope: FundingScope) -> &'static str {
    match scope {
        FundingScope::All => "deployment + operators",
        FundingScope::Deployment => "deployment",
        FundingScope::Operators => "operators",
    }
}

fn manual_review(mut error: AppError, confirmed: usize) -> AppError {
    error.kind = ErrorKind::ReviewRequired;
    error.code = "PARTIAL_FUNDING_REVIEW_REQUIRED";
    error.message = format!(
        "{confirmed} transfer(s) were verified before funding stopped. A transaction may still be pending. Inspect the funding-wallet nonce and receipts before retrying. Cause: {}",
        error.message
    );
    error.next_command = None;
    error
}

#[cfg(test)]
mod tests {
    use ruint::aliases::U256;

    use super::format_eth;

    #[test]
    fn formats_wei_without_float_math() {
        assert_eq!(format_eth(U256::from(1_000_000_000_000_000_u64)), "0.001");
        assert_eq!(format_eth(U256::ZERO), "0");
    }
}
