use std::io::{self, IsTerminal, Write};

use serde::Serialize;

use crate::{VERSION, cli::OutputFormat};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum OutcomeKind {
    Complete,
    ActionRequired,
    ReviewRequired,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
pub struct NextAction {
    pub command: String,
    pub requires_confirmation: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct Check {
    pub id: String,
    pub status: CheckStatus,
    pub message: String,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CheckStatus {
    Pass,
    Warning,
}

#[derive(Debug, Clone, Serialize)]
pub struct Artifact {
    pub kind: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ErrorBody {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CommandOutcome {
    pub schema_version: u32,
    pub cli_version: &'static str,
    pub command: String,
    pub outcome: OutcomeKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_action: Option<NextAction>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub warnings: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub checks: Vec<Check>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub artifacts: Vec<Artifact>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ErrorBody>,
}

impl CommandOutcome {
    pub fn complete(command: impl Into<String>, message: impl Into<String>) -> Self {
        Self::new(command, OutcomeKind::Complete, message)
    }

    pub fn failed(
        command: impl Into<String>,
        code: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        let message = message.into();
        let mut outcome = Self::new(command, OutcomeKind::Failed, &message);
        outcome.error = Some(ErrorBody {
            code: code.into(),
            message,
        });
        outcome
    }

    pub fn error(
        command: impl Into<String>,
        kind: OutcomeKind,
        code: impl Into<String>,
        message: impl Into<String>,
        next_command: Option<String>,
    ) -> Self {
        let message = message.into();
        let mut outcome = Self::new(command, kind, &message);
        outcome.next_action = next_command.map(|command| NextAction {
            command,
            requires_confirmation: false,
        });
        outcome.error = Some(ErrorBody {
            code: code.into(),
            message,
        });
        outcome
    }

    fn new(command: impl Into<String>, outcome: OutcomeKind, message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            cli_version: VERSION,
            command: command.into(),
            outcome,
            stage: None,
            message: message.into(),
            next_action: None,
            warnings: Vec::new(),
            checks: Vec::new(),
            artifacts: Vec::new(),
            data: None,
            error: None,
        }
    }

    pub const fn exit_code(&self) -> i32 {
        match self.outcome {
            OutcomeKind::Complete => 0,
            OutcomeKind::ActionRequired | OutcomeKind::ReviewRequired => 2,
            OutcomeKind::Failed => 1,
        }
    }

    pub fn next(mut self, command: impl Into<String>, requires_confirmation: bool) -> Self {
        self.next_action = Some(NextAction {
            command: command.into(),
            requires_confirmation,
        });
        self
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Reporter {
    format: OutputFormat,
}

impl Reporter {
    pub const fn new(format: OutputFormat) -> Self {
        Self { format }
    }

    pub const fn format(&self) -> OutputFormat {
        self.format
    }

    pub fn progress(&self, message: impl AsRef<str>) {
        match self.format {
            OutputFormat::Human => println!("{}", message.as_ref()),
            OutputFormat::Json => eprintln!("{}", message.as_ref()),
        }
    }

    pub fn finish(&self, outcome: &CommandOutcome) {
        match self.format {
            OutputFormat::Json => render_json(outcome),
            OutputFormat::Human => render_human(outcome),
        }
    }

    pub fn stdin_is_terminal(&self) -> bool {
        io::stdin().is_terminal()
    }

    pub fn stdout_is_terminal(&self) -> bool {
        io::stdout().is_terminal()
    }

    pub fn prompt(&self, prompt: &str) -> io::Result<String> {
        match self.format {
            OutputFormat::Human => {
                print!("{prompt}");
                io::stdout().flush()?;
            }
            OutputFormat::Json => {
                eprint!("{prompt}");
                io::stderr().flush()?;
            }
        }
        let mut answer = String::new();
        io::stdin().read_line(&mut answer)?;
        Ok(answer.trim().to_owned())
    }
}

pub fn render_json(outcome: &CommandOutcome) {
    match serde_json::to_string(outcome) {
        Ok(document) => println!("{document}"),
        Err(error) => eprintln!("Error: could not serialize command outcome: {error}"),
    }
}

fn render_human(outcome: &CommandOutcome) {
    match outcome.outcome {
        OutcomeKind::Complete => println!("{}", outcome.message),
        OutcomeKind::ActionRequired => println!("Action required: {}", outcome.message),
        OutcomeKind::ReviewRequired => eprintln!("Manual review required: {}", outcome.message),
        OutcomeKind::Failed => eprintln!("Error: {}", outcome.message),
    }
    if let Some(stage) = &outcome.stage {
        println!("Stage: {stage}");
    }
    for warning in &outcome.warnings {
        println!("Warning: {warning}");
    }
    if !outcome.checks.is_empty() {
        println!("Checks:");
        for check in &outcome.checks {
            let status = match check.status {
                CheckStatus::Pass => "pass",
                CheckStatus::Warning => "warning",
            };
            println!("  [{status}] {}: {}", check.id, check.message);
        }
    }
    if !outcome.artifacts.is_empty() {
        println!("Artifacts:");
        for artifact in &outcome.artifacts {
            println!("  {}: {}", artifact.kind, artifact.path);
        }
    }
    if let Some(next) = &outcome.next_action {
        println!("Next: {}", next.command);
    }
}
