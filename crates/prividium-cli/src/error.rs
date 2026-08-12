use serde::Serialize;
use thiserror::Error;

use crate::output::{CommandOutcome, OutcomeKind};

#[derive(Debug, Error)]
#[error("{message}")]
pub struct AppError {
    pub code: &'static str,
    pub message: String,
    pub kind: ErrorKind,
    pub next_command: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    Failed,
    ActionRequired,
    ReviewRequired,
}

impl AppError {
    pub fn failed(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            kind: ErrorKind::Failed,
            next_command: None,
        }
    }

    pub fn action(
        code: &'static str,
        message: impl Into<String>,
        next_command: Option<impl Into<String>>,
    ) -> Self {
        Self {
            code,
            message: message.into(),
            kind: ErrorKind::ActionRequired,
            next_command: next_command.map(Into::into),
        }
    }

    pub fn review(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            kind: ErrorKind::ReviewRequired,
            next_command: None,
        }
    }

    pub const fn exit_code(&self) -> i32 {
        match self.kind {
            ErrorKind::Failed => 1,
            ErrorKind::ActionRequired | ErrorKind::ReviewRequired => 2,
        }
    }

    pub fn into_outcome(self, command: impl Into<String>) -> CommandOutcome {
        let outcome = match self.kind {
            ErrorKind::Failed => OutcomeKind::Failed,
            ErrorKind::ActionRequired => OutcomeKind::ActionRequired,
            ErrorKind::ReviewRequired => OutcomeKind::ReviewRequired,
        };
        CommandOutcome::error(command, outcome, self.code, self.message, self.next_command)
    }
}

pub type Result<T> = std::result::Result<T, AppError>;
