# Patty

**Patty: pick your Caddy.**

Patty is a small local web app for turning programs and Caddy routes on and
off. It manages minimal `.pattyfile` profiles, validates every Caddy change,
and exposes route, service, and backend health from one dashboard.

## Requirements

- Caddy available on `PATH`, or configured by full path in Settings
- Crystal 1.20+ and Shards when building from source
- UPX when building on Windows or Linux
- Optional program control:
  - Windows: a Windows service name
  - Linux: a systemd system unit
  - macOS: a Homebrew service

## Build And Run

With [`just`](https://just.systems/):

```text
just setup
just build
just run
```

Windows PowerShell:

```powershell
shards install
just build
.\bin\pattyw.exe
```

macOS or Linux:

```bash
shards install
shards build --release
./bin/patty run
```

Open <http://127.0.0.1:7629>, set the admin password, and create or import a
profile. Use Settings to start Patty automatically after sign-in. On Windows,
this uses the current user's startup registry entry and does not require
administrator access.

To publish Patty's own dashboard through Caddy, open Settings and enter a
hostname such as `patty.example.com` under **Dashboard forwarding**. Patty
validates and manages the reverse-proxy route automatically; clearing the field
removes it. Public forwarding requires HTTPS. The admin password remains
required, and Patty displays a warning until optional authenticator MFA is
enabled. Public DNS and ports 80/443 still need to point to the Caddy machine.

On Windows, running Patty also adds a notification-area icon. Double-click it
to open Patty, or right-click it to open Patty, open the log folder, or exit
cleanly. `pattyw.exe` is the console-free launcher used by shortcuts and
automatic startup; `patty.exe` remains the command-line executable.

The Windows installer uses the checked-in `installer/patty.iss`. Startup is
configured later from Patty's Settings page, not by the installer. Build Patty,
then compile it directly with Inno Setup 7:

```powershell
just build
& "C:\Program Files\Inno Setup 7\ISCC.exe" installer\patty.iss
```

Inno Setup 7 must be installed. Windows and Linux release builds are compressed
with UPX; macOS builds are left uncompressed because UPX does not support them.

## Pattyfiles

A program-backed profile:

```yaml
program: jellyfin

caddy: |
  jellyfin.localhost {
      reverse_proxy 127.0.0.1:8096
  }
```

A Caddy-only file server:

```yaml
caddy: |
  files.localhost {
      root * /srv/files
      file_server
  }
```

`program` is optional and `caddy` is required. No other top-level fields are
accepted. The filename stem is the profile ID and display name, such as
`jellyfin.pattyfile`.

Start first starts the program when present, then enables and validates its
Caddy snippet. Stop first stops the program when present, then disables the
snippet. Failed route changes are rolled back, including compensating service
actions. Caddy-only profiles never invoke a service adapter.

## Public Routes

Patty can configure Caddy, but it cannot create DNS records, router port
forwards, or a running backend.

For a public hostname:

1. Point its DNS record at the server's public IP.
2. Forward TCP ports 80 and 443 to the Caddy machine.
3. Allow Caddy through the host firewall.
4. Make sure `reverse_proxy` targets are reachable from that machine.

The health badge checks the first plain `reverse_proxy` target or file-server
root. An enabled route can therefore show `backend down` or `root missing`
instead of appearing healthy while Caddy returns an error.

Public file servers without obvious Caddy authentication display a security
warning. Patty itself binds to `127.0.0.1` by default; keep it there unless
LAN access is intentional.

## Dashboard Security

Patty is designed to sit behind its locally managed Caddy HTTPS route:

- Passwords are SHA-256 pre-hashed and then bcrypt-hashed at cost 12. Existing
  bcrypt credentials are upgraded after a successful login.
- Optional TOTP MFA works with Google Authenticator and other standard
  authenticator apps. Enrollment provides a QR code, a manual key, and ten
  one-time recovery codes.
- TOTP secrets use Windows DPAPI, macOS Keychain, or Linux Secret Service.
  When no OS vault is available, Patty uses an authenticated AES-256 encrypted
  local key file and displays a warning.
- Login attempts are limited per client IP and process-wide. Security events
  are written to the bounded Patty log without credentials, codes, cookies, or
  request bodies.
- Sessions use `HttpOnly`, `SameSite=Strict`, host-only cookies, adding
  `Secure` behind the trusted local Caddy HTTPS proxy. Sessions expire after
  two idle hours or seven days total.
- Patty sends CSP, frame, MIME-sniffing, referrer, permissions, cache, and HSTS
  protections. Forwarding headers are trusted only from a loopback proxy.
- The public dashboard route is not published while no valid admin credentials
  exist. `reset-password` first removes and reloads that route, then clears the
  password, MFA, and sessions.

Patty never stores or logs plaintext passwords, authenticator codes, recovery
codes, or TOTP secrets. A submitted password or code must briefly exist in the
HTTP request and process memory while it is verified; managed memory cannot
honestly guarantee that every temporary immutable string is immediately
overwritten. Patty keeps those values narrowly scoped and wipes mutable secret
buffers where possible.

## CLI

```text
patty run             Start the web server
patty setup           Show first-run setup hints
patty doctor          Validate configuration, Caddy, services, and routes
patty install         Start Patty automatically after sign-in
patty uninstall       Remove automatic startup
patty reset-password  Clear the admin password
patty reset-mfa       Disable MFA using local machine access
patty version         Show version information
```

## Data And Logs

Patty stores profiles, enabled snippets, backups, configuration, password
hashes, encrypted MFA metadata, and the fallback encryption key under:

- Windows: `%APPDATA%\Patty`
- macOS: `~/Library/Application Support/Patty`
- Linux: `$XDG_DATA_HOME/patty` or `~/.local/share/patty`

Logs are stored in `%LOCALAPPDATA%\Patty\Logs` on Windows,
`~/Library/Logs/Patty` on macOS, and `$XDG_STATE_HOME/patty` or
`~/.local/state/patty` on Linux. Patty keeps bounded action-log rotations and
rotates Caddy output before starting a new Caddy process. The Logs page shows
the latest entries from both files.

`PATTY_HOME=/some/dir` overrides the data directory for portable or test use.

## Development

```bash
shards install
crystal spec
crystal run src/patty.cr -- run
```

The test suite covers Pattyfile parsing, strict validation, filename IDs,
imports, storage, transactional lifecycle behavior, platform adapters, route
health, password upgrades, TOTP vectors, MFA and recovery flows, encrypted
secret tamper detection, throttling, proxy trust, security headers, Caddy
rollback, startup generation, logging, and web behavior.

## Release Scope

Patty 0.1 supports one local administrator, portable Caddy mode, Windows
services, Linux systemd system services, and macOS Homebrew services. It does
not install Caddy, manage DNS/router settings, or run arbitrary commands from
Pattyfiles.
