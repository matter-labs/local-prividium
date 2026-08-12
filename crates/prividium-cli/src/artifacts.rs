use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FundingEvidence {
    pub schema_version: u32,
    pub status: String,
    pub l1_chain_id: u64,
    pub l2_chain_id: u64,
    pub role_set_fingerprint: String,
    pub canary_reserve_wei: String,
    pub funding_targets_sha256: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Preparation {
    pub l2_chain_id: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CanaryAttempt {
    pub l2_chain_id: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CanarySubmission {
    pub l1_chain_id: u64,
    pub l2_chain_id: u64,
    pub canary_address: String,
    pub l1_transaction_hash: String,
    pub l2_transaction_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub struct HappyPathEvidence {
    pub schema_version: u32,
    pub status: String,
    pub l1_chain_id: u64,
    pub l2_chain_id: u64,
    pub authenticated_rpc: bool,
    pub non_admin_oidc: bool,
    pub canary_receipt: bool,
    pub canary_address: String,
    pub l1_transaction_hash: String,
    pub l2_transaction_hash: String,
    pub explorer_indexed: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PublicManifest {
    pub l1_chain_id: u64,
    pub l2_chain_id: u64,
    pub data_availability: DataAvailability,
    pub transaction_filterer: TransactionFilterer,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DataAvailability {
    pub mode: String,
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TransactionFilterer {
    pub deposits_allowed: bool,
}
