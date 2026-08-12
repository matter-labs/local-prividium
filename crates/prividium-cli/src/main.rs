#![forbid(unsafe_code)]

#[tokio::main]
async fn main() {
    std::process::exit(prividium_cli::run_from(std::env::args_os()).await);
}
