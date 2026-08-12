use crate::{
    cli::{CredentialsArgs, CredentialsCommands, OutputFormat},
    context::Context,
    error::{AppError, Result},
    output::{CommandOutcome, Reporter},
    runtime::decrypt_runtime,
};

pub async fn run(
    context: &Context,
    reporter: &Reporter,
    args: CredentialsArgs,
) -> Result<CommandOutcome> {
    match args.command {
        CredentialsCommands::Show => show(context, reporter).await,
    }
}

async fn show(context: &Context, reporter: &Reporter) -> Result<CommandOutcome> {
    if reporter.format() == OutputFormat::Json
        || !reporter.stdin_is_terminal()
        || !reporter.stdout_is_terminal()
    {
        return Err(AppError::failed(
            "INTERACTIVE_TERMINAL_REQUIRED",
            "credentials show requires an interactive terminal and refuses JSON or redirected output",
        ));
    }
    let config = decrypt_runtime(context).await?;
    reporter.progress("Prividium evaluation credentials\n");
    for (label, email_name, password_name) in [
        (
            "Administrator",
            "SANDBOX_ADMIN_EMAIL",
            "SANDBOX_ADMIN_PASSWORD",
        ),
        (
            "Non-admin user 1",
            "SANDBOX_USER_1_EMAIL",
            "SANDBOX_USER_1_PASSWORD",
        ),
        (
            "Non-admin user 2",
            "SANDBOX_USER_2_EMAIL",
            "SANDBOX_USER_2_PASSWORD",
        ),
    ] {
        reporter.progress(format!(
            "{label}\n  Email:    {}\n  Password: {}\n",
            config.required(email_name)?,
            config.required(password_name)?,
        ));
    }
    Ok(CommandOutcome::complete(
        "credentials",
        "Credentials displayed only in this terminal.",
    ))
}
