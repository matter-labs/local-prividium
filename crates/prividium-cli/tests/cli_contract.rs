use std::{path::PathBuf, process::Command};

fn command() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_prividiumcli"));
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("crate must be inside the workspace")
        .to_owned();
    command.current_dir(root);
    command
}

#[test]
fn help_exposes_the_stable_agent_command_surface() {
    let output = command().arg("--help").output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();
    for name in [
        "init",
        "credentials",
        "fund",
        "preflight",
        "prepare",
        "broadcast",
        "deploy",
        "verify",
        "status",
    ] {
        assert!(stdout.contains(name), "help omitted {name}");
    }
}

#[test]
fn invalid_json_invocation_is_one_structured_document() {
    let output = command()
        .args(["--output", "json", "not-a-command"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(64));
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["outcome"], "failed");
    assert_eq!(value["error"]["code"], "INVALID_INVOCATION");
    assert_eq!(String::from_utf8_lossy(&output.stdout).lines().count(), 1);
}

#[test]
fn status_json_is_a_single_resumable_envelope() {
    let output = command()
        .args(["--output", "json", "status"])
        .output()
        .unwrap();
    assert!(output.status.success());
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["command"], "status");
    assert!(value["stage"].is_string());
    assert!(value["data"]["ready"].is_boolean());
    assert_eq!(String::from_utf8_lossy(&output.stdout).lines().count(), 1);
}
