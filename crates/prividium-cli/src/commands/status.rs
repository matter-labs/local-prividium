use std::{fs, path::Path};

use serde::de::DeserializeOwned;
use serde_json::json;

use crate::{
    artifacts::{CanaryAttempt, CanarySubmission, FundingEvidence, HappyPathEvidence, Preparation},
    cli::StatusArgs,
    context::Context,
    error::Result,
    output::{CommandOutcome, NextAction},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Stage {
    ConfigurationRequired,
    FundingRequired,
    Funded,
    BroadcastReviewRequired,
    ReadyToBroadcast,
    DeploymentIncomplete,
    ReadyToDeploy,
    CanaryReviewRequired,
    ReadyToVerify,
    Ready,
}

impl Stage {
    const fn as_str(self) -> &'static str {
        match self {
            Self::ConfigurationRequired => "CONFIGURATION_REQUIRED",
            Self::FundingRequired => "FUNDING_REQUIRED",
            Self::Funded => "FUNDED",
            Self::BroadcastReviewRequired => "BROADCAST_REVIEW_REQUIRED",
            Self::ReadyToBroadcast => "READY_TO_BROADCAST",
            Self::DeploymentIncomplete => "DEPLOYMENT_INCOMPLETE",
            Self::ReadyToDeploy => "READY_TO_DEPLOY",
            Self::CanaryReviewRequired => "CANARY_REVIEW_REQUIRED",
            Self::ReadyToVerify => "READY_TO_VERIFY",
            Self::Ready => "READY",
        }
    }
}

struct Status {
    stage: Stage,
    ready: bool,
    next_command: Option<&'static str>,
    detail: &'static str,
    l2_chain_id: Option<u64>,
}

pub fn run(context: &Context, _args: StatusArgs) -> Result<CommandOutcome> {
    let status = calculate(context);
    let mut outcome = CommandOutcome::complete("status", status.detail);
    outcome.stage = Some(status.stage.as_str().to_owned());
    outcome.next_action = status.next_command.map(|command| NextAction {
        command: command.to_owned(),
        requires_confirmation: matches!(
            status.stage,
            Stage::ReadyToBroadcast | Stage::ReadyToVerify
        ),
    });
    outcome.data = Some(json!({
        "ready": status.ready,
        "l2_chain_id": status.l2_chain_id,
        "profile": "sandbox",
        "core_only": true,
    }));
    Ok(outcome)
}

fn calculate(context: &Context) -> Status {
    let funding =
        read_json::<FundingEvidence>(&context.runtime_dir.join("reports/funding-ready.json"));
    let preparation =
        read_json::<Preparation>(&context.runtime_dir.join("chain/out/preparation.json"));
    let manifest = read_json::<serde_json::Value>(&context.public("manifest.json"));
    let happy = read_json::<HappyPathEvidence>(&context.public("happy-path.json"));
    let protected_happy =
        read_json::<HappyPathEvidence>(&context.runtime_dir.join("reports/happy-path.json"));
    let canary_attempt =
        read_json::<CanaryAttempt>(&context.runtime_dir.join("chain/canary-attempt.json"));
    let canary_submission =
        read_json::<CanarySubmission>(&context.runtime_dir.join("chain/canary-submission.json"));
    let canary_launch = context
        .runtime_dir
        .join("reports/canary-attempt.json")
        .is_file();
    let l2_chain_id = happy
        .as_ref()
        .map(|value| value.l2_chain_id)
        .or_else(|| {
            manifest
                .as_ref()
                .and_then(|value| value.get("l2_chain_id")?.as_u64())
        })
        .or_else(|| preparation.as_ref().map(|value| value.l2_chain_id))
        .or_else(|| funding.as_ref().map(|value| value.l2_chain_id));

    let (stage, next_command, detail) = if !context.encrypted_environment().is_file() {
        (
            Stage::ConfigurationRequired,
            Some("prividiumcli init"),
            "Complete the protected input file and initialize the sandbox.",
        )
    } else if preparation.is_none() && manifest.is_none() {
        if valid_funding(funding.as_ref()) {
            (
                Stage::Funded,
                Some("prividiumcli preflight"),
                "Funding was reconciled; pass preflight and prepare the protocol deployment.",
            )
        } else {
            (
                Stage::FundingRequired,
                Some("prividiumcli fund"),
                "Reconcile the Sepolia roles and retain the acceptance-canary reserve.",
            )
        }
    } else if manifest.is_none()
        && context
            .runtime_dir
            .join("reports/broadcast-attempt.json")
            .exists()
    {
        (
            Stage::BroadcastReviewRequired,
            None,
            "An approved protocol broadcast was interrupted; preserve runtime state and inspect it before any retry.",
        )
    } else if manifest.is_none() {
        (
            Stage::ReadyToBroadcast,
            Some("prividiumcli broadcast"),
            "Review the prepared artifacts and explicitly authorize the Sepolia broadcast.",
        )
    } else if context
        .runtime_dir
        .join("reports/deployment-summary.incomplete.md")
        .is_file()
    {
        (
            Stage::DeploymentIncomplete,
            Some("prividiumcli deploy"),
            "Resolve the protected deployment diagnostics and resume the core stack.",
        )
    } else if !context.public("deployment-summary.md").is_file() {
        (
            Stage::ReadyToDeploy,
            Some("prividiumcli deploy"),
            "Start and validate the 14-service core stack.",
        )
    } else if valid_happy(happy.as_ref(), protected_happy.as_ref()) {
        (
            Stage::Ready,
            None,
            "Authenticated RPC, the canary receipt, and Explorer indexing are complete.",
        )
    } else if (canary_attempt.is_some() || canary_launch)
        && !valid_canary(canary_attempt.as_ref(), canary_submission.as_ref())
    {
        (
            Stage::CanaryReviewRequired,
            None,
            "An approved canary was interrupted before durable submission evidence; inspect Sepolia state before retrying.",
        )
    } else {
        (
            Stage::ReadyToVerify,
            Some("prividiumcli verify"),
            "Run the confirmation-gated authenticated canary and Explorer smoke.",
        )
    };

    Status {
        stage,
        ready: stage == Stage::Ready,
        next_command,
        detail,
        l2_chain_id,
    }
}

fn read_json<T: DeserializeOwned>(path: &Path) -> Option<T> {
    serde_json::from_slice(&fs::read(path).ok()?).ok()
}

fn valid_funding(value: Option<&FundingEvidence>) -> bool {
    value.is_some_and(|value| {
        value.schema_version == 1
            && value.status == "FUNDED"
            && value.l1_chain_id == 11_155_111
            && (crate::config::MIN_L2_CHAIN_ID..=crate::config::MAX_L2_CHAIN_ID)
                .contains(&value.l2_chain_id)
            && value.role_set_fingerprint.len() == 64
            && value
                .canary_reserve_wei
                .starts_with(|character: char| character.is_ascii_digit() && character != '0')
            && value.funding_targets_sha256.len() == 64
    })
}

fn valid_happy(public: Option<&HappyPathEvidence>, protected: Option<&HappyPathEvidence>) -> bool {
    public.zip(protected).is_some_and(|(public, protected)| {
        public == protected
            && public.schema_version == 1
            && public.status == "READY"
            && public.l1_chain_id == 11_155_111
            && (crate::config::MIN_L2_CHAIN_ID..=crate::config::MAX_L2_CHAIN_ID)
                .contains(&public.l2_chain_id)
            && public.authenticated_rpc
            && public.non_admin_oidc
            && public.canary_receipt
            && is_hex(&public.canary_address, 40)
            && is_hex(&public.l1_transaction_hash, 64)
            && is_hex(&public.l2_transaction_hash, 64)
            && public.explorer_indexed
    })
}

fn valid_canary(attempt: Option<&CanaryAttempt>, submission: Option<&CanarySubmission>) -> bool {
    match (attempt, submission) {
        (Some(attempt), Some(submission)) => {
            submission.l1_chain_id == 11_155_111
                && submission.l2_chain_id == attempt.l2_chain_id
                && is_hex(&submission.canary_address, 40)
                && is_hex(&submission.l1_transaction_hash, 64)
                && is_hex(&submission.l2_transaction_hash, 64)
        }
        _ => false,
    }
}

fn is_hex(value: &str, digits: usize) -> bool {
    value.strip_prefix("0x").is_some_and(|value| {
        value.len() == digits && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

#[cfg(test)]
mod tests {
    use crate::artifacts::HappyPathEvidence;

    use super::{is_hex, valid_happy};

    #[test]
    fn validates_fixed_width_hex() {
        assert!(is_hex(&format!("0x{}", "a".repeat(64)), 64));
        assert!(!is_hex("0x1234", 64));
    }

    #[test]
    fn ready_requires_matching_protected_evidence() {
        let evidence = HappyPathEvidence {
            schema_version: 1,
            status: "READY".to_owned(),
            l1_chain_id: 11_155_111,
            l2_chain_id: crate::config::MIN_L2_CHAIN_ID,
            authenticated_rpc: true,
            non_admin_oidc: true,
            canary_receipt: true,
            canary_address: format!("0x{}", "a".repeat(40)),
            l1_transaction_hash: format!("0x{}", "b".repeat(64)),
            l2_transaction_hash: format!("0x{}", "c".repeat(64)),
            explorer_indexed: true,
        };
        assert!(valid_happy(Some(&evidence), Some(&evidence)));
        assert!(!valid_happy(Some(&evidence), None));
    }
}
