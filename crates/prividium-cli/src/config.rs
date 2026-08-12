use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::Path,
};

use secrecy::{ExposeSecret, SecretString};

use crate::error::{AppError, Result};

pub const MIN_L2_CHAIN_ID: u64 = 1_073_741_824;
pub const MAX_L2_CHAIN_ID: u64 = 2_147_483_647;

#[derive(Debug)]
pub struct InputConfig {
    pub domain: String,
    pub acme_email: String,
    pub sepolia_rpc_url: SecretString,
    pub sepolia_browser_rpc_url: String,
    pub l2_chain_id: Option<u64>,
}

#[derive(Debug)]
pub struct RuntimeConfig {
    values: BTreeMap<String, SecretString>,
}

impl RuntimeConfig {
    pub fn parse(document: &str) -> Result<Self> {
        let values = parse_env(document, false)?
            .into_iter()
            .map(|(name, value)| (name, SecretString::from(value)))
            .collect();
        let config = Self { values };
        config.required("SANDBOX_DOMAIN")?;
        config.l2_chain_id()?;
        if config.required("RUNTIME_DIR")? != "/etc/prividium/runtime" {
            return Err(AppError::failed(
                "INVALID_RUNTIME_CONFIGURATION",
                "RUNTIME_DIR must be /etc/prividium/runtime",
            ));
        }
        Ok(config)
    }

    pub fn required(&self, name: &str) -> Result<&str> {
        self.values
            .get(name)
            .map(|value| value.expose_secret())
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                AppError::failed(
                    "RUNTIME_VALUE_MISSING",
                    format!("protected runtime is missing {name}"),
                )
            })
    }

    pub fn l2_chain_id(&self) -> Result<u64> {
        let value = self
            .required("L2_CHAIN_ID")?
            .parse()
            .map_err(|_| AppError::failed("INVALID_CHAIN_ID", "L2_CHAIN_ID must be numeric"))?;
        validate_chain_id(value)?;
        Ok(value)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &str)> {
        self.values
            .iter()
            .map(|(name, value)| (name.as_str(), value.expose_secret()))
    }
}

impl InputConfig {
    pub fn load(path: &Path) -> Result<Self> {
        let metadata = fs::symlink_metadata(path).map_err(|error| {
            AppError::failed("INPUT_FILE_MISSING", format!("{}: {error}", path.display()))
        })?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(AppError::failed(
                "UNSAFE_INPUT_FILE",
                "input must be a regular file",
            ));
        }
        if metadata.uid() != crate::fs::current_uid()?
            || metadata.permissions().mode() & 0o777 != 0o600
        {
            return Err(AppError::failed(
                "UNSAFE_INPUT_FILE",
                "input must be owned by the current operator with mode 0600",
            ));
        }
        let document = fs::read_to_string(path).map_err(|error| {
            AppError::failed("INPUT_READ_FAILED", format!("{}: {error}", path.display()))
        })?;
        let mut values = parse_env(&document, true)?;
        let required = [
            "SANDBOX_DOMAIN",
            "ACME_EMAIL",
            "SEPOLIA_RPC_URL",
            "SEPOLIA_BROWSER_RPC_URL",
        ];
        for name in required {
            if !values.contains_key(name) {
                return Err(AppError::failed(
                    "INPUT_VALUE_MISSING",
                    format!("{name} is required"),
                ));
            }
        }
        let allowed = [
            "SANDBOX_DOMAIN",
            "ACME_EMAIL",
            "SEPOLIA_RPC_URL",
            "SEPOLIA_BROWSER_RPC_URL",
            "L2_CHAIN_ID",
        ];
        if let Some(name) = values.keys().find(|name| !allowed.contains(&name.as_str())) {
            return Err(AppError::failed(
                "INPUT_VALUE_UNKNOWN",
                format!("unknown input value {name}"),
            ));
        }
        let domain = values.remove("SANDBOX_DOMAIN").unwrap_or_default();
        let acme_email = values.remove("ACME_EMAIL").unwrap_or_default();
        let private_rpc = values.remove("SEPOLIA_RPC_URL").unwrap_or_default();
        let browser_rpc = values.remove("SEPOLIA_BROWSER_RPC_URL").unwrap_or_default();
        validate_domain(&domain)?;
        validate_email(&acme_email)?;
        validate_rpc_url(&private_rpc)?;
        validate_rpc_url(&browser_rpc)?;
        if private_rpc.trim_end_matches('/') == browser_rpc.trim_end_matches('/') {
            return Err(AppError::failed(
                "RPC_URLS_NOT_DISTINCT",
                "private and browser RPC URLs must be separate",
            ));
        }
        let l2_chain_id = values
            .remove("L2_CHAIN_ID")
            .filter(|value| !value.is_empty())
            .map(|value| {
                value.parse::<u64>().map_err(|_| {
                    AppError::failed("INVALID_CHAIN_ID", "L2_CHAIN_ID must be numeric")
                })
            })
            .transpose()?;
        if let Some(chain_id) = l2_chain_id {
            validate_chain_id(chain_id)?;
        }
        Ok(Self {
            domain,
            acme_email,
            sepolia_rpc_url: SecretString::from(private_rpc),
            sepolia_browser_rpc_url: browser_rpc,
            l2_chain_id,
        })
    }
}

pub fn validate_profile(profile: &str) -> Result<()> {
    if profile == "sandbox" {
        Ok(())
    } else {
        Err(AppError::failed(
            "UNSUPPORTED_PROFILE",
            format!("unsupported profile '{profile}'; supported profile: sandbox"),
        ))
    }
}

pub fn validate_chain_id(value: u64) -> Result<()> {
    if (MIN_L2_CHAIN_ID..=MAX_L2_CHAIN_ID).contains(&value) {
        Ok(())
    } else {
        Err(AppError::failed(
            "INVALID_CHAIN_ID",
            format!("L2_CHAIN_ID must be in {MIN_L2_CHAIN_ID}..{MAX_L2_CHAIN_ID}"),
        ))
    }
}

pub fn validate_domain(domain: &str) -> Result<()> {
    if domain.len() > 253 || !domain.contains('.') || domain.contains("..") {
        return Err(AppError::failed(
            "INVALID_DOMAIN",
            "SANDBOX_DOMAIN is invalid",
        ));
    }
    if domain.split('.').all(valid_domain_label) {
        Ok(())
    } else {
        Err(AppError::failed(
            "INVALID_DOMAIN",
            "SANDBOX_DOMAIN is invalid",
        ))
    }
}

pub fn validate_email(email: &str) -> Result<()> {
    let valid = email.split_once('@').is_some_and(|(local, domain)| {
        !local.is_empty()
            && !domain.is_empty()
            && local
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"._%+-".contains(&byte))
            && domain
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'.' || byte == b'-')
    });
    if valid {
        Ok(())
    } else {
        Err(AppError::failed("INVALID_EMAIL", "ACME_EMAIL is invalid"))
    }
}

pub fn validate_rpc_url(value: &str) -> Result<()> {
    let parsed = url::Url::parse(value).map_err(|_| {
        AppError::failed(
            "INVALID_RPC_URL",
            "Sepolia RPC URLs must be valid HTTPS URLs",
        )
    })?;
    if parsed.scheme() == "https" && parsed.host_str().is_some() && parsed.fragment().is_none() {
        Ok(())
    } else {
        Err(AppError::failed(
            "INVALID_RPC_URL",
            "Sepolia RPC URLs must use HTTPS",
        ))
    }
}

fn parse_env(document: &str, reject_duplicates: bool) -> Result<BTreeMap<String, String>> {
    let mut values = BTreeMap::new();
    for (index, raw) in document.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (name, raw_value) = line.split_once('=').ok_or_else(|| {
            AppError::failed(
                "INVALID_ENV_FILE",
                format!("line {} is not NAME=value", index + 1),
            )
        })?;
        if !valid_env_name(name) {
            return Err(AppError::failed(
                "INVALID_ENV_NAME",
                format!("invalid name on line {}", index + 1),
            ));
        }
        let value = unquote(raw_value).map_err(|message| {
            AppError::failed(
                "INVALID_ENV_VALUE",
                format!("line {}: {message}", index + 1),
            )
        })?;
        if value.contains(['\0', '\n', '\r']) {
            return Err(AppError::failed(
                "INVALID_ENV_VALUE",
                format!("line {} contains a forbidden character", index + 1),
            ));
        }
        if reject_duplicates && values.contains_key(name) {
            return Err(AppError::failed(
                "DUPLICATE_ENV_VALUE",
                format!("{name} appears more than once"),
            ));
        }
        values.insert(name.to_owned(), value);
    }
    Ok(values)
}

fn valid_env_name(name: &str) -> bool {
    let mut bytes = name.bytes();
    bytes.next().is_some_and(|byte| byte.is_ascii_uppercase())
        && bytes.all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
}

fn valid_domain_label(label: &str) -> bool {
    !label.is_empty()
        && label.len() <= 63
        && label
            .as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
        && label
            .as_bytes()
            .last()
            .is_some_and(u8::is_ascii_alphanumeric)
        && label
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

fn unquote(value: &str) -> std::result::Result<String, &'static str> {
    let value = if let Some(value) = value.strip_prefix('"') {
        value
            .strip_suffix('"')
            .map(str::to_owned)
            .ok_or("unterminated double quote")?
    } else if let Some(value) = value.strip_prefix('\'') {
        value
            .strip_suffix('\'')
            .map(str::to_owned)
            .ok_or("unterminated single quote")?
    } else {
        value.to_owned()
    };
    if value.contains(['"', '\'', '`', '$', '\\']) {
        Err("shell syntax and escapes are not allowed")
    } else {
        Ok(value)
    }
}

#[cfg(test)]
mod tests {
    use super::{MAX_L2_CHAIN_ID, MIN_L2_CHAIN_ID, parse_env, validate_chain_id};

    #[test]
    fn accepts_an_omitted_high_range_chain_id() {
        let values = parse_env("SANDBOX_DOMAIN=sandbox.example.com\n", true).unwrap();
        assert!(!values.contains_key("L2_CHAIN_ID"));
        assert!(validate_chain_id(MIN_L2_CHAIN_ID).is_ok());
        assert!(validate_chain_id(MAX_L2_CHAIN_ID).is_ok());
    }

    #[test]
    fn rejects_duplicate_or_shell_shaped_input() {
        assert!(parse_env("A=one\nA=two\n", true).is_err());
        assert!(parse_env("A=$(id)\n", true).is_err());
        assert!(parse_env("A=$VALUE\n", true).is_err());
        assert!(parse_env("A=`id`\n", true).is_err());
        assert!(parse_env("A=one\\two\n", true).is_err());
    }
}
