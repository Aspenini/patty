# Patty

**Pick your Caddy.**

Patty is a local web app for turning apps and Caddy routes on and off. You write
small `.pattyfile` profiles, Patty validates the Caddy config, and you manage
everything from one dashboard.

## Quick start

Build and run (needs [Crystal](https://crystal-lang.org/) and [just](https://just.systems/)):

```bash
just setup
just build
just run
```

Open <http://127.0.0.1:7629>, set an admin password, and add a profile.

Windows: `just run` launches `pattyw.exe` (tray icon, no console). Use
`patty.exe` from the terminal for CLI commands.

## Pattyfiles

Put profiles in Patty's data folder. The filename is the profile name, e.g.
`jellyfin.pattyfile`.

```yaml
program: jellyfin

caddy: |
  jellyfin.localhost {
      reverse_proxy 127.0.0.1:8096
  }
```

`program` is optional (starts/stops a Windows service, systemd unit, or
Homebrew service). `caddy` is required.

Caddy-only example:

```yaml
caddy: |
  files.localhost {
      root * /srv/files
      file_server
  }
```

## CLI

```text
patty run             Start the web server
patty doctor          Check Caddy, services, and routes
patty install         Start Patty after sign-in
patty uninstall       Remove automatic startup
patty reset-password  Clear the admin password
patty reset-mfa       Disable MFA
patty version         Show version
```

## Where stuff lives

- **Data** (profiles, config, auth): `%APPDATA%\Patty` (Windows),
  `~/Library/Application Support/Patty` (macOS), `~/.local/share/patty` (Linux)
- **Logs**: `%LOCALAPPDATA%\Patty\Logs` (Windows), `~/Library/Logs/Patty`
  (macOS), `~/.local/state/patty` (Linux)

Set `PATTY_HOME` to use a different data directory.

## Notes

- Caddy must be on `PATH` or configured in Settings.
- Patty binds to `127.0.0.1` by default.
- Optional MFA and dashboard forwarding are in Settings.
