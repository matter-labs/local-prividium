use std::{
    env, fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

use sha2::{Digest, Sha256};

use crate::{
    config::RuntimeConfig,
    context::Context,
    error::{AppError, Result},
    fs::{atomic_write, ensure_private_directory, ensure_regular_file},
    process::{CommandSpec, require_commands},
};

pub async fn decrypt_runtime(context: &Context) -> Result<RuntimeConfig> {
    ensure_encrypted_environment(context)?;
    let age_identity = resolve_age_identity(context)?;
    let output = CommandSpec::new("sops")
        .args([
            "--decrypt",
            "--input-type",
            "dotenv",
            "--output-type",
            "dotenv",
        ])
        .arg(context.encrypted_environment())
        .env("SOPS_AGE_KEY_FILE", age_identity)
        .checked("SOPS decryption")
        .await?;
    parse_runtime_bytes(output)
}

pub async fn materialize_runtime(context: &Context) -> Result<RuntimeConfig> {
    ensure_private_directory(&context.runtime_dir)?;
    ensure_encrypted_environment(context)?;
    let age_identity = resolve_age_identity(context)?;
    let output = CommandSpec::new("sops")
        .args([
            "--decrypt",
            "--input-type",
            "dotenv",
            "--output-type",
            "dotenv",
        ])
        .arg(context.encrypted_environment())
        .env("SOPS_AGE_KEY_FILE", age_identity)
        .checked("SOPS decryption")
        .await?;
    let config = parse_runtime_bytes(output.clone())?;
    atomic_write(&context.runtime_environment(), 0o600, &output, true)?;
    Ok(config)
}

pub fn load_runtime(context: &Context) -> Result<RuntimeConfig> {
    ensure_private_directory(&context.runtime_dir)?;
    ensure_regular_file(&context.runtime_environment(), Some(0o600)).map_err(|_| {
        AppError::action(
            "RUNTIME_ENVIRONMENT_REQUIRED",
            "protected runtime environment is missing or unsafe; run prepare",
            Some("prividiumcli prepare"),
        )
    })?;
    let document = fs::read_to_string(context.runtime_environment())
        .map_err(|error| AppError::failed("RUNTIME_READ_FAILED", error.to_string()))?;
    RuntimeConfig::parse(&document)
}

pub fn ensure_encrypted_environment(context: &Context) -> Result<()> {
    ensure_regular_file(&context.encrypted_environment(), None).map_err(|_| {
        AppError::action(
            "CONFIGURATION_REQUIRED",
            "encrypted sandbox configuration is missing; run init",
            Some("prividiumcli init"),
        )
    })?;
    let mode = fs::symlink_metadata(context.encrypted_environment())
        .map_err(|error| AppError::failed("CONFIGURATION_READ_FAILED", error.to_string()))?
        .permissions()
        .mode()
        & 0o777;
    if mode & 0o022 != 0 {
        return Err(AppError::failed(
            "UNSAFE_CONFIGURATION_MODE",
            "encrypted configuration must not be group/world writable",
        ));
    }
    Ok(())
}

pub fn resolve_age_identity(context: &Context) -> Result<PathBuf> {
    require_commands("Age identity resolution", &["age-keygen", "sops"])?;
    let path = env::var_os("SOPS_AGE_KEY_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| context.age_key());
    ensure_regular_file(&path, None)?;
    let mode = fs::symlink_metadata(&path)
        .map_err(|error| AppError::failed("AGE_IDENTITY_READ_FAILED", error.to_string()))?
        .permissions()
        .mode()
        & 0o777;
    if mode & 0o077 != 0 {
        return Err(AppError::failed(
            "UNSAFE_AGE_IDENTITY_MODE",
            format!("{} must not grant group/world permissions", path.display()),
        ));
    }
    Ok(path)
}

pub fn sha256_file(path: &Path) -> Result<String> {
    let bytes = fs::read(path).map_err(|error| {
        AppError::failed("FILE_READ_FAILED", format!("{}: {error}", path.display()))
    })?;
    Ok(hex::encode(Sha256::digest(bytes)))
}

fn parse_runtime_bytes(output: Vec<u8>) -> Result<RuntimeConfig> {
    let document = String::from_utf8(output).map_err(|_| {
        AppError::failed(
            "INVALID_RUNTIME_CONFIGURATION",
            "decrypted configuration is not UTF-8",
        )
    })?;
    RuntimeConfig::parse(&document)
}
