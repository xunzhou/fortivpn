# fortivpn

`fortivpn` is a small launcher that configures an OpenFortiVPN gateway, opens
`openfortivpn-webview` for SAML authentication, and streams the resulting cookie
directly to OpenFortiVPN. The cookie is never stored or placed in process argv.

## Install with Nix

```bash
nix profile install .#fortivpn
```

## Build on Arch Linux

Install the AUR dependency `openfortivpn-webview-qt`, then build the native
package:

```bash
makepkg --syncdeps --install
```

## Configure and connect

```bash
fortivpn config
fortivpn
fortivpn disconnect
```

Configuration is written outside this repository to
`${XDG_CONFIG_HOME:-$HOME/.config}/openfortivpn/config`. The launcher accepts a
gateway host and port only. It rejects unsafe ownership, symlinks, and any group
or other access before authentication. For each foreground connection it copies
the validated configuration into a mode-`0700` temporary directory as a
mode-`0600` snapshot, uses that same snapshot for the webview gateway and
OpenFortiVPN, and removes it when the launcher exits. `fortivpn disconnect`
sends SIGINT to running OpenFortiVPN processes through `sudo`, matching the
foreground Ctrl-C shutdown path.

## Security boundary

Do not commit VPN configuration, credentials, cookies, authentication output,
internal hostnames, routes, or work logs. The webview cookie travels only over
the pipe into `openfortivpn --cookie-on-stdin`. `sudo -v` completes before the
webview opens. The temporary configuration snapshot contains no cookie and
prevents a persistent configuration change during privilege acquisition from
giving the webview and OpenFortiVPN different gateway settings.

## Test

```bash
bats tests/*.bats
nix flake check -L
makepkg --cleanbuild --noconfirm
```

The automated suite uses `vpn.example.com` and synthetic cookies. It does not
contact a real identity provider or VPN.

## Optional i3 toggle

Install the click-action helper with:

```bash
install -Dm 0755 contrib/i3-vpn-toggle ~/.local/bin/i3-vpn-toggle
```

The helper launches `fortivpn` in an Alacritty window with the exact class
`forti`. While authentication is in progress, clicking again closes that
terminal. Once `ppp0` is connected, clicking opens a terminal that runs
`fortivpn disconnect`, allowing `sudo` to prompt if needed. It requires
`i3-msg`, `ip`, `jq`, and Alacritty, plus `flock` from util-linux. As with i3
itself, it expects `XDG_RUNTIME_DIR` to identify the per-user runtime directory.
The helper resolves `fortivpn` from `PATH` by default; set
`FORTIVPN_EXECUTABLE` to use a specific launcher path.

## Manual acceptance

1. Record local DNS and route state without copying it into this repository.
2. Run `fortivpn config` and verify the file is owned by you with mode `0600`.
3. Run `fortivpn`, complete SAML, and reach one approved work endpoint.
4. Confirm only intended DNS and routes changed.
5. Press Ctrl-C and confirm the PPP interface disappears and ordinary DNS and
   routes return.

Record only pass/fail and package versions. Do not record the gateway, internal
hostnames, route values, cookie, credentials, or authentication logs.

## Scope

V1 intentionally has no status, remote-connect, cookie-only, or
profile-management commands. Ctrl-C or `fortivpn disconnect` ends the
foreground connection.
