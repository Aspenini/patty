# Patty

**Patty — pick your Caddy.**

A Crystal-powered local web app for managing installed apps and their Caddy
routes. Create or import simple `.pattyfile` profiles, then start/stop apps
and enable/disable their Caddy routes from a clean dashboard — no Docker
stack, no giant frontend, no manual terminal juggling.

## Quickstart

```bash
brew install crystal caddy   # caddy via go install works too
shards install
shards build --release

bin/patty run
```

Then open <http://localhost:7629>, set an admin password, and create your
first profile.

## A profile is just this

```yaml
patty: 1

name: Jellyfin
program: jellyfin

caddy: |
  jellyfin.localhost {
      reverse_proxy 127.0.0.1:8096
  }
```

Pressing **Start** starts the program (via Homebrew services on macOS),
enables the Caddy snippet, validates the config, and reloads Caddy.
**Stop** does the reverse. Validation always happens *before* anything is
applied — a broken snippet never reaches your Caddy.

## CLI

The CLI only launches and recovers; everything else is in the web UI.

```text
patty run             Start the web server
patty setup           First-run setup hints
patty doctor          Check if the system is ready
patty reset-password  Clear the admin password
patty version         Version info
```

## Running Caddy (portable mode)

Patty v0.0 manages snippets in its own data dir and generates a main
Caddyfile that imports them. Run Caddy against it:

```bash
caddy run --config "$HOME/Library/Application Support/Patty/active/Caddyfile" --adapter caddyfile
```

The Settings page shows all paths.

## Development

```bash
shards install
crystal spec
crystal run src/patty.cr -- run
```

`PATTY_HOME=/some/dir` overrides the data directory (specs use this).

## Status

v0.0 — macOS dev build. Homebrew services adapter, portable Caddy mode,
profile create/import/export, safe validate→backup→apply→reload flow,
admin password auth. Linux (systemd) and Windows adapters come later via
the same adapter interface.
