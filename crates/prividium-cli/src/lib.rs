#![forbid(unsafe_code)]

pub mod artifacts;
pub mod cli;
pub mod commands;
pub mod compose;
pub mod config;
pub mod context;
pub mod error;
pub mod fs;
pub mod oidc;
pub mod output;
pub mod process;
pub mod roles;
pub mod rpc;
pub mod runtime;

use std::ffi::OsString;

use clap::{Parser, error::ErrorKind};

use crate::{
    cli::{Cli, Commands, OutputFormat},
    context::Context,
    error::AppError,
    output::{CommandOutcome, Reporter},
};

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

pub async fn run_from<I, T>(args: I) -> i32
where
    I: IntoIterator<Item = T>,
    T: Into<OsString> + Clone,
{
    let raw: Vec<OsString> = args.into_iter().map(Into::into).collect();
    let requested_json = raw.windows(2).any(|pair| {
        pair[0] == "--output" && pair[1].to_string_lossy().eq_ignore_ascii_case("json")
    }) || raw
        .iter()
        .any(|arg| arg == "--output=json" || arg == "--json");

    let cli = match Cli::try_parse_from(raw) {
        Ok(cli) => cli,
        Err(error)
            if matches!(
                error.kind(),
                ErrorKind::DisplayHelp | ErrorKind::DisplayVersion
            ) =>
        {
            let _ = error.print();
            return 0;
        }
        Err(error) => {
            if requested_json {
                let outcome = CommandOutcome::failed(
                    "cli",
                    "INVALID_INVOCATION",
                    error.to_string().trim().to_owned(),
                );
                output::render_json(&outcome);
            } else {
                let _ = error.print();
            }
            return 64;
        }
    };

    let format = cli.effective_output();
    let reporter = Reporter::new(format);
    let context = match Context::discover() {
        Ok(context) => context,
        Err(error) => return render_error(format, "cli", error),
    };
    let command_name = cli.command.name();

    let result = dispatch(&context, &reporter, cli.command).await;
    match result {
        Ok(outcome) => {
            reporter.finish(&outcome);
            outcome.exit_code()
        }
        Err(error) => render_error(format, command_name, error),
    }
}

fn render_error(format: OutputFormat, command: &'static str, error: AppError) -> i32 {
    let exit_code = error.exit_code();
    Reporter::new(format).finish(&error.into_outcome(command));
    exit_code
}

async fn dispatch(
    context: &Context,
    reporter: &Reporter,
    command: Commands,
) -> Result<CommandOutcome, AppError> {
    match command {
        Commands::Status(args) => commands::status::run(context, args),
        Commands::Init(args) => commands::init::run(context, reporter, args).await,
        Commands::Credentials(args) => commands::credentials::run(context, reporter, args).await,
        Commands::Fund(args) => commands::fund::run(context, reporter, args).await,
        Commands::Preflight(args) => commands::preflight::run(context, reporter, args).await,
        Commands::Prepare(args) => commands::prepare::run(context, reporter, args).await,
        Commands::Broadcast(args) => commands::broadcast::run(context, reporter, args).await,
        Commands::Deploy(args) => commands::deploy::run(context, reporter, args).await,
        Commands::Verify(args) => commands::verify::run(context, reporter, args).await,
    }
}
