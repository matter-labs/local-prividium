use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "prividiumcli",
    version,
    about = "Deploy and verify the Prividium evaluation sandbox",
    disable_help_subcommand = true
)]
pub struct Cli {
    /// Result format. JSON emits one machine-readable document to stdout.
    #[arg(long, global = true, default_value = "human", value_name = "FORMAT")]
    pub output: OutputFormat,

    #[command(subcommand)]
    pub command: Commands,
}

impl Cli {
    pub fn effective_output(&self) -> OutputFormat {
        if matches!(&self.command, Commands::Status(StatusArgs { json: true })) {
            OutputFormat::Json
        } else {
            self.output
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum OutputFormat {
    Human,
    Json,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    /// Initialize an evaluation sandbox.
    Init(InitArgs),
    /// Reveal generated evaluation credentials.
    Credentials(CredentialsArgs),
    /// Fund identities required for protocol deployment.
    Fund(FundArgs),
    /// Check deployment readiness before protocol preparation.
    Preflight(ProfileArgs),
    /// Prepare runtime state and simulate protocol deployment.
    Prepare(ProfileArgs),
    /// Broadcast the prepared protocol deployment to Sepolia.
    Broadcast(ProfileArgs),
    /// Start and validate the sandbox services.
    Deploy(ProfileArgs),
    /// Run the confirmation-gated authenticated product smoke.
    Verify(ProfileArgs),
    /// Show the resumable deployment stage and next action.
    Status(StatusArgs),
}

impl Commands {
    pub const fn name(&self) -> &'static str {
        match self {
            Self::Init(_) => "init",
            Self::Credentials(_) => "credentials",
            Self::Fund(_) => "fund",
            Self::Preflight(_) => "preflight",
            Self::Prepare(_) => "prepare",
            Self::Broadcast(_) => "broadcast",
            Self::Deploy(_) => "deploy",
            Self::Verify(_) => "verify",
            Self::Status(_) => "status",
        }
    }
}

#[derive(Debug, Args)]
pub struct InitArgs {
    #[arg(long, default_value = "sandbox")]
    pub profile: String,
    #[arg(long, default_value = "deployment/input.env", value_name = "PATH")]
    pub env_file: PathBuf,
}

#[derive(Debug, Args)]
pub struct CredentialsArgs {
    #[command(subcommand)]
    pub command: CredentialsCommands,
}

#[derive(Debug, Subcommand)]
pub enum CredentialsCommands {
    /// Print generated evaluation credentials to an interactive terminal.
    Show,
}

#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub enum FundingScope {
    All,
    Deployment,
    Operators,
}

#[derive(Debug, Args)]
pub struct FundArgs {
    #[arg(value_enum, default_value = "all")]
    pub scope: FundingScope,
    #[arg(long, default_value = "sandbox")]
    pub profile: String,
    #[arg(long)]
    pub list: bool,
}

#[derive(Debug, Args)]
pub struct ProfileArgs {
    #[arg(long, default_value = "sandbox")]
    pub profile: String,
}

#[derive(Debug, Args)]
pub struct StatusArgs {
    /// Alias for --output json.
    #[arg(long)]
    pub json: bool,
}
