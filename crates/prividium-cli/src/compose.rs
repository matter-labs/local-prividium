use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

use serde_json::Value;

use crate::{
    config::RuntimeConfig,
    context::Context,
    error::{AppError, Result},
    output::Reporter,
    process::{CommandOutput, CommandSpec},
};

const CHAIN_BOOTSTRAP_TAG: &str = "local/zk-deployer:16c6a83-protocol-e091691";

pub struct Compose<'a> {
    context: &'a Context,
    environment: PathBuf,
}

impl<'a> Compose<'a> {
    pub fn new(context: &'a Context, environment: impl Into<PathBuf>) -> Self {
        Self {
            context,
            environment: environment.into(),
        }
    }

    pub async fn validate(&self) -> Result<()> {
        for module in [
            "platform.yaml",
            "permissioning.yaml",
            "explorer.yaml",
            "monitoring.yaml",
            "optional.yaml",
            "demos.yaml",
        ] {
            if !self
                .context
                .repo_root
                .join("compose")
                .join(module)
                .is_file()
            {
                return Err(AppError::failed(
                    "COMPOSE_MODULE_MISSING",
                    format!("compose/{module} is missing"),
                ));
            }
        }
        let model = self
            .command()
            .args(["config", "--format", "json"])
            .checked("Compose model rendering")
            .await?;
        let model: Value = serde_json::from_slice(&model)
            .map_err(|error| AppError::failed("COMPOSE_MODEL_INVALID", error.to_string()))?;
        let services = model
            .get("services")
            .and_then(Value::as_object)
            .ok_or_else(|| {
                AppError::failed("COMPOSE_MODEL_INVALID", "services object is missing")
            })?;
        let actual: BTreeSet<_> = services.keys().map(String::as_str).collect();
        let expected: BTreeSet<_> = [
            "admin-panel",
            "block-explorer-api",
            "block-explorer-app",
            "block-explorer-data-fetcher",
            "block-explorer-worker",
            "caddy",
            "chain-preflight",
            "grafana",
            "keycloak",
            "operator-balance-exporter",
            "postgres",
            "prividium-api",
            "prometheus",
            "user-panel",
            "zksyncos",
        ]
        .into_iter()
        .collect();
        if actual != expected {
            return Err(AppError::failed(
                "COMPOSE_SERVICE_SET_INVALID",
                "default Compose model must contain exactly 14 long-running services and chain-preflight",
            ));
        }
        let buildable: BTreeSet<_> = services
            .iter()
            .filter_map(|(name, service)| service.get("build").map(|_| name.as_str()))
            .collect();
        if buildable
            != ["chain-preflight", "operator-balance-exporter"]
                .into_iter()
                .collect()
        {
            return Err(AppError::failed(
                "COMPOSE_BUILD_SET_INVALID",
                "only chain-preflight and operator-balance-exporter may build locally",
            ));
        }
        for (name, service) in services {
            let expected_restart = if name == "chain-preflight" {
                "no"
            } else {
                "unless-stopped"
            };
            if service.get("restart").and_then(Value::as_str) != Some(expected_restart) {
                return Err(AppError::failed(
                    "COMPOSE_RESTART_POLICY_INVALID",
                    format!("service {name} has an invalid restart policy"),
                ));
            }
        }
        let images = self
            .command()
            .args([
                "--profile",
                "chain-bootstrap",
                "--profile",
                "sso",
                "--profile",
                "webhook",
                "--profile",
                "institutional-demo",
                "config",
                "--images",
            ])
            .checked("Compose image rendering")
            .await?;
        for image in String::from_utf8_lossy(&images)
            .lines()
            .filter(|line| !line.is_empty())
        {
            if !image.starts_with("local/") && !image.contains("@sha256:") {
                return Err(AppError::failed(
                    "UNPINNED_REMOTE_IMAGE",
                    format!("remote image is not digest-pinned: {image}"),
                ));
            }
        }
        Ok(())
    }

    pub async fn images(&self, prepared_image: Option<&str>) -> Result<Vec<String>> {
        let mut command = self.command();
        if let Some(image) = prepared_image {
            command = command.env("PRIVIDIUM_CHAIN_BOOTSTRAP_IMAGE", image);
        }
        let output = command
            .args(["config", "--images"])
            .checked("Compose image rendering")
            .await?;
        let mut images: Vec<_> = String::from_utf8_lossy(&output)
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(str::to_owned)
            .collect();
        images.sort();
        images.dedup();
        Ok(images)
    }

    pub async fn pull_locked(&self) -> Result<()> {
        self.checked(
            self.command().args(["pull", "--ignore-buildable"]),
            "locked image pull",
        )
        .await
    }

    pub async fn build_operator_exporter(&self) -> Result<()> {
        self.checked(
            self.command().args(["build", "operator-balance-exporter"]),
            "operator-balance-exporter build",
        )
        .await
    }

    pub async fn up(&self, prepared_image: &str) -> Result<()> {
        self.checked(
            self.command()
                .env("PRIVIDIUM_CHAIN_BOOTSTRAP_IMAGE", prepared_image)
                .args(["up", "-d", "--no-build", "--pull", "never"]),
            "core stack startup",
        )
        .await
    }

    pub async fn service_id(&self, service: &str, profile: Option<&str>) -> Result<Option<String>> {
        let mut command = self.command();
        if let Some(profile) = profile {
            command = command.args(["--profile", profile]);
        }
        let output = command
            .args(["ps", "--all", "-q", service])
            .output("Compose service lookup")
            .await?;
        if !output.status.success() {
            return Err(AppError::failed(
                "COMPOSE_SERVICE_LOOKUP_FAILED",
                format!("could not inspect Compose service {service}"),
            ));
        }
        let id = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        Ok((!id.is_empty()).then_some(id))
    }

    pub async fn container_state(&self, container_id: &str) -> Result<String> {
        let output = CommandSpec::new("docker")
            .args([
                "inspect",
                "--format",
                "{{.State.Status}}|{{.State.ExitCode}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}",
                container_id,
            ])
            .output("container state inspection")
            .await?;
        if !output.status.success() {
            return Err(AppError::failed(
                "CONTAINER_INSPECTION_FAILED",
                "could not inspect a core container",
            ));
        }
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
    }

    pub async fn exec_postgres(&self, sql: &str) -> Result<String> {
        let output = self
            .command()
            .args([
                "exec",
                "-T",
                "postgres",
                "/bin/sh",
                "-ec",
                "PGPASSWORD=\"$POSTGRES_PASSWORD\" exec psql -U \"$POSTGRES_USER\" -d \"$EXPLORER_DB_NAME\" -Atc \"$1\"",
                "sh",
                sql,
            ])
            .checked("Explorer database query")
            .await?;
        Ok(String::from_utf8_lossy(&output).trim().to_owned())
    }

    pub async fn chain_bootstrap(
        &self,
        mode: &str,
        config: &RuntimeConfig,
        reporter: &Reporter,
        confirmation: Option<&str>,
    ) -> Result<String> {
        let prepared_image = if mode == "prepare" {
            self.checked(
                self.command()
                    .env("CHAIN_BOOTSTRAP_MODE", "prepare")
                    .env("PRIVIDIUM_HOST_UID", current_id("-u")?)
                    .env("PRIVIDIUM_HOST_GID", current_id("-g")?)
                    .args(["--profile", "chain-bootstrap", "build", "chain-bootstrap"]),
                "chain-bootstrap image build",
            )
            .await?;
            let output = CommandSpec::new("docker")
                .args([
                    "image",
                    "inspect",
                    CHAIN_BOOTSTRAP_TAG,
                    "--format",
                    "{{.Id}}",
                ])
                .checked("chain-bootstrap image inspection")
                .await?;
            String::from_utf8_lossy(&output).trim().to_owned()
        } else if mode == "broadcast" {
            let record: Value = serde_json::from_slice(
                &fs::read(self.context.runtime_dir.join("chain/out/preparation.json")).map_err(
                    |_| AppError::failed("PREPARATION_REQUIRED", "preparation record is missing"),
                )?,
            )
            .map_err(|error| AppError::failed("PREPARATION_INVALID", error.to_string()))?;
            let image = record
                .get("chain_bootstrap_image_id")
                .and_then(Value::as_str)
                .filter(|value| valid_image_id(value))
                .ok_or_else(|| {
                    AppError::failed("PREPARATION_INVALID", "prepared image identity is missing")
                })?;
            let output = CommandSpec::new("docker")
                .args(["image", "inspect", image])
                .output("prepared image inspection")
                .await?;
            if !output.status.success() {
                return Err(AppError::failed(
                    "PREPARED_IMAGE_MISSING",
                    "the exact chain-bootstrap image used during simulation is missing",
                ));
            }
            image.to_owned()
        } else {
            return Err(AppError::failed(
                "INVALID_BOOTSTRAP_MODE",
                "bootstrap mode must be prepare or broadcast",
            ));
        };
        if !valid_image_id(&prepared_image) {
            return Err(AppError::failed(
                "PREPARED_IMAGE_INVALID",
                "Docker returned an invalid chain-bootstrap image identity",
            ));
        }
        let confirmation = confirmation.unwrap_or_default();
        let output = self
            .command()
            .env("CHAIN_BOOTSTRAP_MODE", mode)
            .env("PRIVIDIUM_HOST_UID", current_id("-u")?)
            .env("PRIVIDIUM_HOST_GID", current_id("-g")?)
            .env("PRIVIDIUM_CHAIN_BOOTSTRAP_IMAGE", &prepared_image)
            .env("CONFIRM_BROADCAST", confirmation)
            .args([
                "--profile",
                "chain-bootstrap",
                "run",
                "--rm",
                "--no-build",
                "--pull",
                "never",
                "-e",
                &format!("BOOTSTRAP_MODE={mode}"),
                "-e",
                &format!("CONFIRM_BROADCAST={confirmation}"),
                "-e",
                &format!("PREPARED_IMAGE_ID={prepared_image}"),
                "chain-bootstrap",
            ])
            .output("chain bootstrap")
            .await?;
        let sanitized = sanitize_output(config, &output);
        if !sanitized.is_empty() {
            reporter.progress(sanitized);
        }
        if !output.status.success() {
            return Err(AppError::failed(
                "CHAIN_BOOTSTRAP_FAILED",
                format!("chain bootstrap {mode} failed"),
            ));
        }
        Ok(prepared_image)
    }

    pub async fn canary(
        &self,
        config: &RuntimeConfig,
        reporter: &Reporter,
        confirmation: &str,
    ) -> Result<()> {
        let preparation: Value = serde_json::from_slice(
            &fs::read(self.context.runtime_dir.join("chain/out/preparation.json")).map_err(
                |_| AppError::failed("PREPARATION_REQUIRED", "preparation record is missing"),
            )?,
        )
        .map_err(|error| AppError::failed("PREPARATION_INVALID", error.to_string()))?;
        let image = preparation
            .get("chain_bootstrap_image_id")
            .and_then(Value::as_str)
            .filter(|value| valid_image_id(value))
            .ok_or_else(|| {
                AppError::failed("PREPARATION_INVALID", "prepared image identity is missing")
            })?;
        let inspect = CommandSpec::new("docker")
            .args(["image", "inspect", image])
            .output("prepared image inspection")
            .await?;
        if !inspect.status.success() {
            return Err(AppError::failed(
                "PREPARED_IMAGE_MISSING",
                "the exact chain-bootstrap image used during simulation is missing",
            ));
        }
        let output = self
            .command()
            .env("PRIVIDIUM_CHAIN_BOOTSTRAP_IMAGE", image)
            .env("CONFIRM_CANARY", confirmation)
            .args([
                "--profile",
                "chain-bootstrap",
                "run",
                "--rm",
                "--no-build",
                "--pull",
                "never",
                "--entrypoint",
                "/usr/local/bin/prividium-canary",
                "-e",
                &format!("CONFIRM_CANARY={confirmation}"),
                "chain-bootstrap",
            ])
            .output("acceptance canary")
            .await?;
        let sanitized = sanitize_output(config, &output);
        if !sanitized.is_empty() {
            reporter.progress(sanitized);
        }
        if output.status.success() {
            Ok(())
        } else {
            Err(AppError::failed(
                "CANARY_SUBMISSION_FAILED",
                "acceptance canary container failed",
            ))
        }
    }

    fn command(&self) -> CommandSpec {
        CommandSpec::new("docker")
            .arg("compose")
            .arg("-f")
            .arg(self.context.repo_root.join("compose/compose.yaml"))
            .arg("--env-file")
            .arg(&self.environment)
            .current_dir(&self.context.repo_root)
    }

    async fn checked(&self, command: CommandSpec, operation: &'static str) -> Result<()> {
        let output = command.output(operation).await?;
        if output.status.success() {
            Ok(())
        } else {
            Err(AppError::failed(
                "COMPOSE_COMMAND_FAILED",
                format!(
                    "{operation} failed: {}",
                    String::from_utf8_lossy(&output.stderr).trim()
                ),
            ))
        }
    }
}

fn sanitize_output(config: &RuntimeConfig, output: &CommandOutput) -> String {
    let mut document = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    for (_, value) in config.iter().filter(|(name, _)| sensitive_name(name)) {
        if !value.is_empty() {
            document = document.replace(value, "[hidden]");
            if let Some(unprefixed) = value.strip_prefix("0x") {
                document = document.replace(unprefixed, "[hidden]");
            }
        }
    }
    document.trim().to_owned()
}

fn sensitive_name(name: &str) -> bool {
    [
        "PRIVATE_KEY",
        "PASSWORD",
        "RPC_URL",
        "KEYSTORE",
        "SECRET",
        "API_KEY",
        "ENCRYPTION_KEY",
    ]
    .iter()
    .any(|marker| name.contains(marker))
}

fn valid_image_id(value: &str) -> bool {
    value.strip_prefix("sha256:").is_some_and(|value| {
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

fn current_id(flag: &str) -> Result<String> {
    let output = std::process::Command::new("id")
        .arg(flag)
        .output()
        .map_err(|error| AppError::failed("IDENTITY_LOOKUP_FAILED", error.to_string()))?;
    if !output.status.success() {
        return Err(AppError::failed(
            "IDENTITY_LOOKUP_FAILED",
            format!("id {flag} failed"),
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

pub fn ensure_nonempty_regular(path: &Path, label: &str) -> Result<()> {
    let metadata = fs::symlink_metadata(path).map_err(|_| {
        AppError::failed(
            "RUNTIME_ARTIFACT_MISSING",
            format!("{label} is missing: {}", path.display()),
        )
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() || metadata.len() == 0 {
        return Err(AppError::failed(
            "RUNTIME_ARTIFACT_UNSAFE",
            format!("{label} is missing or unsafe: {}", path.display()),
        ));
    }
    Ok(())
}
