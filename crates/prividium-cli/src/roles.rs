use std::collections::{BTreeMap, BTreeSet};

use k256::{
    SecretKey,
    elliptic_curve::{rand_core::OsRng, sec1::ToEncodedPoint},
};
use secrecy::{ExposeSecret, SecretString};
use sha2::{Digest as Sha2Digest, Sha256};
use sha3::Keccak256;

use crate::{
    config::RuntimeConfig,
    error::{AppError, Result},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoleScope {
    Core,
    Optional,
}

#[derive(Debug, Clone, Copy)]
pub struct RoleDefinition {
    pub id: &'static str,
    pub key_name: &'static str,
    pub label: &'static str,
    pub purpose: &'static str,
    pub group: Option<&'static str>,
    pub scope: RoleScope,
}

pub const ROLES: &[RoleDefinition] = &[
    RoleDefinition {
        id: "l1_deployer",
        key_name: "L1_DEPLOYER_PRIVATE_KEY",
        label: "Ecosystem deployer",
        purpose: "Deploys the dedicated Sepolia ecosystem and chain contracts.",
        group: Some("deployment"),
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "ecosystem_governor",
        key_name: "ECOSYSTEM_GOVERNOR_PRIVATE_KEY",
        label: "Ecosystem governor",
        purpose: "Approves ecosystem governance actions during bootstrap.",
        group: Some("deployment"),
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "chain_owner",
        key_name: "CHAIN_OWNER_PRIVATE_KEY",
        label: "Chain owner",
        purpose: "Approves chain administration actions during bootstrap.",
        group: Some("deployment"),
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "operator_commit",
        key_name: "OPERATOR_COMMIT_PRIVATE_KEY",
        label: "Commit operator",
        purpose: "Submits L1 batch commitments.",
        group: Some("operators"),
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "operator_prove",
        key_name: "OPERATOR_PROVE_PRIVATE_KEY",
        label: "Prove operator",
        purpose: "Submits L1 proof transactions.",
        group: Some("operators"),
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "operator_execute",
        key_name: "OPERATOR_EXECUTE_PRIVATE_KEY",
        label: "Execute operator",
        purpose: "Executes settled L1 batches.",
        group: Some("operators"),
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "bridge_sponsor",
        key_name: "BRIDGE_SPONSOR_PRIVATE_KEY",
        label: "Sandbox funding wallet",
        purpose: "Receives customer funding, distributes L1 ETH, and submits the acceptance self-deposit.",
        group: None,
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "fee_account",
        key_name: "FEE_ACCOUNT_PRIVATE_KEY",
        label: "Fee account",
        purpose: "Receives protocol fees and does not submit L1 transactions.",
        group: None,
        scope: RoleScope::Core,
    },
    RoleDefinition {
        id: "bundler",
        key_name: "BUNDLER_PRIVATE_KEY",
        label: "Bundler",
        purpose: "Optional SSO transaction bundler.",
        group: None,
        scope: RoleScope::Optional,
    },
    RoleDefinition {
        id: "entrypoint_deployer",
        key_name: "ENTRYPOINT_DEPLOYER_PRIVATE_KEY",
        label: "EntryPoint deployer",
        purpose: "Optional one-time EntryPoint deployment wallet.",
        group: None,
        scope: RoleScope::Optional,
    },
    RoleDefinition {
        id: "sso_deployer",
        key_name: "SSO_DEPLOYER_PRIVATE_KEY",
        label: "SSO contract deployer",
        purpose: "Optional SSO contract deployment wallet.",
        group: None,
        scope: RoleScope::Optional,
    },
    RoleDefinition {
        id: "auth_server",
        key_name: "AUTH_SERVER_PRIVATE_KEY",
        label: "SSO auth server",
        purpose: "Optional SSO auth-server transaction wallet.",
        group: None,
        scope: RoleScope::Optional,
    },
    RoleDefinition {
        id: "auth_server_admin",
        key_name: "AUTH_SERVER_ADMIN_PRIVATE_KEY",
        label: "SSO administrative wallet",
        purpose: "Optional SSO administrative permission wallet.",
        group: None,
        scope: RoleScope::Optional,
    },
    RoleDefinition {
        id: "institutional_demo_deployer",
        key_name: "INSTITUTIONAL_DEMO_DEPLOYER_PRIVATE_KEY",
        label: "Institutional demo deployer",
        purpose: "Optional institutional-demo deployment wallet.",
        group: None,
        scope: RoleScope::Optional,
    },
];

#[derive(Debug)]
pub struct RoleSet {
    private_keys: BTreeMap<&'static str, SecretString>,
    addresses: BTreeMap<&'static str, String>,
}

impl RoleSet {
    pub fn generate_with(
        override_role: &'static str,
        override_key: Option<SecretString>,
    ) -> Result<Self> {
        let private_keys = ROLES
            .iter()
            .map(|role| {
                if role.id == override_role
                    && let Some(key) = override_key.as_ref()
                {
                    return (role.id, SecretString::from(key.expose_secret().to_owned()));
                }
                let secret = SecretKey::random(&mut OsRng);
                (
                    role.id,
                    SecretString::from(format!("0x{}", hex::encode(secret.to_bytes()))),
                )
            })
            .collect();
        Self::from_private_keys(private_keys)
    }

    pub fn from_runtime(config: &RuntimeConfig) -> Result<Self> {
        let private_keys = ROLES
            .iter()
            .map(|role| {
                config
                    .required(role.key_name)
                    .map(|value| (role.id, SecretString::from(value.to_owned())))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        Self::from_private_keys(private_keys)
    }

    fn from_private_keys(private_keys: BTreeMap<&'static str, SecretString>) -> Result<Self> {
        let addresses = private_keys
            .iter()
            .map(|(role, key)| {
                address_from_private_key(key.expose_secret()).map(|address| (*role, address))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        let distinct: BTreeSet<_> = addresses
            .values()
            .map(|address| address.to_ascii_lowercase())
            .collect();
        if distinct.len() != ROLES.len() {
            return Err(AppError::failed(
                "DUPLICATE_ROLE_IDENTITY",
                "every sandbox role must use a distinct private key",
            ));
        }
        Ok(Self {
            private_keys,
            addresses,
        })
    }

    pub fn address(&self, id: &str) -> Result<&str> {
        self.addresses
            .get(id)
            .map(String::as_str)
            .ok_or_else(|| AppError::failed("UNKNOWN_ROLE", format!("unknown role {id}")))
    }

    pub fn fingerprint(&self) -> String {
        let mut canonical = String::new();
        for role in ROLES {
            canonical.push_str(role.id);
            canonical.push('=');
            canonical.push_str(&self.addresses[role.id].to_ascii_lowercase());
            canonical.push('\n');
        }
        hex::encode(Sha256::digest(canonical.as_bytes()))
    }

    pub fn secret_pairs(&self) -> impl Iterator<Item = (&'static str, &str)> {
        ROLES
            .iter()
            .map(|role| (role.key_name, self.private_keys[role.id].expose_secret()))
    }
}

pub fn address_from_private_key(value: &str) -> Result<String> {
    let bytes = hex::decode(value.strip_prefix("0x").unwrap_or(value)).map_err(|_| {
        AppError::failed(
            "INVALID_PRIVATE_KEY",
            "private key must be 32-byte hexadecimal",
        )
    })?;
    let secret = SecretKey::from_slice(&bytes).map_err(|_| {
        AppError::failed(
            "INVALID_PRIVATE_KEY",
            "private key is not a valid secp256k1 scalar",
        )
    })?;
    let public = secret.public_key().to_encoded_point(false);
    let digest = Keccak256::digest(&public.as_bytes()[1..]);
    Ok(checksum_address(&hex::encode(&digest[12..])))
}

fn checksum_address(lower_hex: &str) -> String {
    let lower_hex = lower_hex.to_ascii_lowercase();
    let hash = hex::encode(Keccak256::digest(lower_hex.as_bytes()));
    let mut result = String::from("0x");
    for (index, character) in lower_hex.chars().enumerate() {
        let nibble = u8::from_str_radix(&hash[index..index + 1], 16).unwrap_or_default();
        if character.is_ascii_alphabetic() && nibble >= 8 {
            result.push(character.to_ascii_uppercase());
        } else {
            result.push(character);
        }
    }
    result
}

pub fn role_report(domain: &str, chain_id: u64, roles: &RoleSet) -> Result<String> {
    let mut report = format!(
        "# Prividium sandbox role inventory\n\nThis non-secret inventory was generated by `prividiumcli init`. It groups all\nsandbox identities by purpose and never contains private keys.\n\n- Sandbox domain: `{domain}`\n- Ethereum settlement network: Sepolia (`11155111`)\n- L2 chain ID: `{chain_id}`\n- Role-set fingerprint: `{}`.\n\n## Chain deployment and governance\n\n",
        roles.fingerprint()
    );
    for role in ROLES.iter().filter(|role| role.group == Some("deployment")) {
        report.push_str(&format!(
            "- **{}** — `{}` — {}\n",
            role.label,
            roles.address(role.id)?,
            role.purpose
        ));
    }
    report.push_str("\n## Settlement operators\n\n");
    for role in ROLES.iter().filter(|role| role.group == Some("operators")) {
        report.push_str(&format!(
            "- **{}** — `{}` — {}\n",
            role.label,
            roles.address(role.id)?,
            role.purpose
        ));
    }
    report.push_str("\n## Sandbox funding\n\n> Customer action: send only the amount requested by `prividiumcli fund` to:\n>\n");
    report.push_str(&format!("> `{}`\n\n", roles.address("bridge_sponsor")?));
    report.push_str("## Service and passive accounts\n\n");
    for role in ROLES.iter().filter(|role| role.group.is_none()) {
        let scope = match role.scope {
            RoleScope::Core => "Core",
            RoleScope::Optional => "Optional",
        };
        report.push_str(&format!(
            "- **{}** ({scope}) — `{}` — {}\n",
            role.label,
            roles.address(role.id)?,
            role.purpose
        ));
    }
    Ok(report)
}

pub fn role(id: &str) -> Result<&'static RoleDefinition> {
    ROLES
        .iter()
        .find(|role| role.id == id)
        .ok_or_else(|| AppError::failed("UNKNOWN_ROLE", format!("unknown role {id}")))
}

#[cfg(test)]
mod tests {
    use super::address_from_private_key;

    #[test]
    fn derives_known_ethereum_address() {
        let address = address_from_private_key(
            "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        )
        .unwrap();
        assert_eq!(address, "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c");
    }
}
