use std::{
    collections::BTreeMap,
    ffi::{OsStr, OsString},
    path::PathBuf,
    process::{ExitStatus, Stdio},
};

use tokio::process::Command;
use zeroize::Zeroizing;

use crate::error::{AppError, Result};

#[derive(Default)]
pub struct CommandSpec {
    program: OsString,
    args: Vec<OsString>,
    env: BTreeMap<OsString, OsString>,
    stdin: Option<Zeroizing<Vec<u8>>>,
    current_dir: Option<PathBuf>,
}

pub struct CommandOutput {
    pub status: ExitStatus,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl CommandSpec {
    pub fn new(program: impl Into<OsString>) -> Self {
        Self {
            program: program.into(),
            ..Self::default()
        }
    }

    pub fn arg(mut self, arg: impl Into<OsString>) -> Self {
        self.args.push(arg.into());
        self
    }

    pub fn args<I, S>(mut self, args: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<OsString>,
    {
        self.args.extend(args.into_iter().map(Into::into));
        self
    }

    pub fn env(mut self, name: impl Into<OsString>, value: impl Into<OsString>) -> Self {
        self.env.insert(name.into(), value.into());
        self
    }

    pub fn stdin(mut self, value: impl Into<Vec<u8>>) -> Self {
        self.stdin = Some(Zeroizing::new(value.into()));
        self
    }

    pub fn current_dir(mut self, value: impl Into<PathBuf>) -> Self {
        self.current_dir = Some(value.into());
        self
    }

    pub async fn output(self, context: &'static str) -> Result<CommandOutput> {
        let mut command = Command::new(&self.program);
        command.args(&self.args).envs(&self.env);
        if let Some(directory) = &self.current_dir {
            command.current_dir(directory);
        }
        command.stdout(Stdio::piped()).stderr(Stdio::piped());
        if self.stdin.is_some() {
            command.stdin(Stdio::piped());
        }
        let mut child = command.spawn().map_err(|error| {
            AppError::failed(
                "COMMAND_START_FAILED",
                format!("could not start {context}: {error}"),
            )
        })?;
        if let Some(stdin) = self.stdin {
            use tokio::io::AsyncWriteExt;
            let mut child_stdin = child.stdin.take().ok_or_else(|| {
                AppError::failed(
                    "COMMAND_STDIN_FAILED",
                    format!("could not open stdin for {context}"),
                )
            })?;
            child_stdin.write_all(&stdin).await.map_err(|error| {
                AppError::failed(
                    "COMMAND_STDIN_FAILED",
                    format!("could not write stdin for {context}: {error}"),
                )
            })?;
        }
        let output = child.wait_with_output().await.map_err(|error| {
            AppError::failed(
                "COMMAND_WAIT_FAILED",
                format!("could not wait for {context}: {error}"),
            )
        })?;
        Ok(CommandOutput {
            status: output.status,
            stdout: output.stdout,
            stderr: output.stderr,
        })
    }

    pub async fn checked(self, context: &'static str) -> Result<Vec<u8>> {
        let output = self.output(context).await?;
        if !output.status.success() {
            let detail = String::from_utf8_lossy(&output.stderr);
            return Err(AppError::failed(
                "COMMAND_FAILED",
                format!("{context} failed: {}", detail.trim()),
            ));
        }
        Ok(output.stdout)
    }
}

pub fn command_exists(program: impl AsRef<OsStr>) -> bool {
    let program = program.as_ref();
    if program.to_string_lossy().contains('/') {
        return std::path::Path::new(program).is_file();
    }
    std::env::var_os("PATH")
        .is_some_and(|paths| std::env::split_paths(&paths).any(|path| path.join(program).is_file()))
}

pub fn require_commands(context: &'static str, commands: &[&str]) -> Result<()> {
    let missing: Vec<_> = commands
        .iter()
        .copied()
        .filter(|command| !command_exists(command))
        .collect();
    if missing.is_empty() {
        Ok(())
    } else {
        Err(AppError::failed(
            "DEPENDENCY_MISSING",
            format!(
                "missing commands required for {context}: {}",
                missing.join(", ")
            ),
        ))
    }
}
