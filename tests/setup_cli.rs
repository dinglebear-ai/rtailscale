use std::{fs, process::Command};

fn tailscale_bin() -> &'static str {
    env!("CARGO_BIN_EXE_rtailscale")
}

fn make_fake_binary(dir: &std::path::Path) {
    let path = dir.join("tailscale");
    fs::write(&path, "#!/usr/bin/env sh\nexit 0\n").unwrap();
    let mut perms = fs::metadata(&path).unwrap().permissions();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        perms.set_mode(0o755);
    }
    fs::set_permissions(path, perms).unwrap();
}

#[test]
fn setup_plugin_hook_no_repair_json_contract() {
    let home = tempfile::tempdir().unwrap();
    let bin_dir = tempfile::tempdir().unwrap();
    make_fake_binary(bin_dir.path());

    let output = Command::new(tailscale_bin())
        .args(["--json", "setup", "plugin-hook", "--no-repair"])
        .env("TAILSCALE_MCP_HOME", home.path().join(".tailscale-test"))
        .env("PATH", bin_dir.path())
        .output()
        .unwrap();

    assert!(
        !output.status.success(),
        "no-repair should report missing appdata/env as blocking"
    );
    let payload: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(payload["exit_policy"], "blocking_failure");
    assert_eq!(payload["ran_repair"], false);
    assert_eq!(payload["no_repair"], true);
    assert!(payload["blocking_failures"]
        .as_array()
        .unwrap()
        .iter()
        .any(|value| value == "appdata_dir"));
    assert!(payload["advisory_failures"]
        .as_array()
        .unwrap()
        .iter()
        .any(|value| value == "env_file"));
    assert!(!home.path().join(".tailscale-test").exists());
}

/// `setup plugin-hook` is an explicit CLI command (the plugin ships no Claude
/// Code hooks). This verifies `apply_plugin_options()` maps
/// `CLAUDE_PLUGIN_OPTION_*` into the `TAILSCALE_*` env vars the setup checks
/// read: `CLAUDE_PLUGIN_DATA` reaches `appdata_dir` and
/// `CLAUDE_PLUGIN_OPTION_MCP_PORT` reaches `port_check`.
#[test]
fn plugin_hook_maps_plugin_options_into_env() {
    let data = tempfile::tempdir().unwrap();
    let bin_dir = tempfile::tempdir().unwrap();
    make_fake_binary(bin_dir.path());
    let appdata = data.path().join("appdata");
    fs::create_dir_all(&appdata).unwrap();

    // A free high port to prove the option flows into port_check.
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let port = listener.local_addr().unwrap().port();
    drop(listener);

    let output = Command::new(tailscale_bin())
        .args(["--json", "setup", "plugin-hook", "--no-repair"])
        .env_remove("TAILSCALE_MCP_PORT")
        .env("PATH", bin_dir.path())
        .env("TAILSCALE_MCP_HOME", &appdata)
        .env("CLAUDE_PLUGIN_OPTION_MCP_PORT", port.to_string())
        .output()
        .unwrap();

    let payload: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    // appdata_dir resolves to CLAUDE_PLUGIN_DATA (mapped to TAILSCALE_MCP_HOME).
    let appdata_detail = payload["check"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["name"] == "appdata_dir")
        .map(|c| c["detail"].as_str().unwrap_or_default().to_string())
        .unwrap_or_default();
    assert_eq!(appdata_detail, appdata.display().to_string());

    // port_check targets the mapped CLAUDE_PLUGIN_OPTION_MCP_PORT value.
    let port_detail = payload["check"]["checks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["name"] == "mcp_port")
        .map(|c| c["detail"].as_str().unwrap_or_default().to_string())
        .unwrap_or_default();
    assert!(
        port_detail.contains(&port.to_string()),
        "port_check detail should mention mapped port {port}, got: {port_detail}"
    );
}

/// The plugin intentionally ships no Claude Code hooks.
#[test]
fn plugin_ships_no_hooks() {
    let plugin_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("plugins/tailscale");
    assert!(
        !plugin_root.join("hooks").exists(),
        "plugins/tailscale/hooks must not exist"
    );
    let manifest: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(plugin_root.join(".claude-plugin/plugin.json")).unwrap(),
    )
    .unwrap();
    assert!(
        manifest.get("hooks").is_none(),
        "plugin manifest must not declare hooks"
    );
}
