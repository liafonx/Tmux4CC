# Proxy setup (Xray): Claude VLESS entry, Mini exit and qBittorrent tunnel

This file describes the final Xray setup as of 2026-10-05. The VPS is the only public entry. The Mac Mini has no public
port and only exits traffic through a reverse tunnel. Real secrets (UUIDs, keys, passwords, links) are not in this repo.
The two `*.config.tmpl.json` files are the live configs with placeholders.

## Topology

```
Claude user ──VLESS Encryption + Vision──▶ VPS 88.151.34.29:8443 (sub.liafonx.net, tag claude-vless)
                                             TCP to allow-list (21 domains, 160.79.104.0/21) → r-client, else block
VPS service (Docker or host) ──SOCKS5──▶  VPS :10810 (tag mini-exit)
                                             source 172.16.0.0/12 or 127.0.0.0/8 → r-client, else block
                                                 │  one VLESS reverse tunnel (the Mini dials OUT to liatech.eu.org:54451)
                                                 ▼
                                           Mac Mini  inbound "r-client"
                                             1. domain qb.invalid:54904 → qb-local → qBittorrent 127.0.0.1:54904
                                             2. everything else        → direct-out (dial-time guard: private ranges blocked)
                                                 ▼
                                           Destinations see the MAC MINI's IP.

qBittorrent (bound to lo0)  ─▶ 127.0.0.1:10801 (qb-socks) ─▶ UUID-F (forward only) ─▶ VPS ─▶ internet   (exit = VPS IP)
peers ─▶ VPS:54904 (r-server, destination qb.invalid:54904) ─▶ reverse tunnel ─▶ qBittorrent             (inbound via VPS)
```

| Host | Port | Tag | Role |
|---|---|---|---|
| VPS | 0.0.0.0:8443 | `claude-vless` | VLESS Encryption (`native`, X25519 auth) + Vision, raw TCP, no TLS. Clients `owner@claude`, `bai@claude` |
| VPS | 0.0.0.0:10810 | `mini-exit` | SOCKS5, user `vps` + password, `udp` off. Mini-IP exit for VPS services |
| VPS | 54451 | `vless-in` | The Mini's reverse bridge (UUID-R) and forward-only client (UUID-F) |
| VPS | 54904 | `r-server` | qB inbound peers, TCP and UDP |
| VPS | 443 | – | Caddy (`bark.liafonx.net`), not Xray |
| Mini | 127.0.0.1:10801 | `qb-socks` | qB's SOCKS5 proxy, routed to `to-vps-fwd` |

UUID-R is reverse-only and UUID-F is forward-only (Xray ≥ 25.12.2 refuses a reverse UUID as a forward one). Each
Claude user has one UUID on 8443. The 8443 key differs from the 54451 key.

## Files and secrets

| File | Deployed path |
|---|---|
| `vps-xray.config.tmpl.json` | VPS `/usr/local/etc/xray/config.json` (root:nogroup 640, runs as `nobody` under `xray.service`) |
| `mini-xray.config.tmpl.json` | Mini `/usr/local/etc/xray/config.json` (600, root LaunchDaemon `homebrew.mxcl.xray`) |

- Placeholders: `<UUID_R_REVERSE_ONLY>`, `<UUID_F_FORWARD_ONLY>` (both hosts), `<VLESS_DECRYPTION_TUNNEL>` (VPS 54451)
  and its Mini pair `<VLESS_ENCRYPTION>`, `<VLESS_DECRYPTION_CLAUDE>` (8443), `<UUID_OWNER>`, `<UUID_BAI>`, `<MINI_EXIT_PASS>`.
- Generate keys with `xray vlessenc` (X25519 variant) and UUIDs with `xray uuid`.
- DNS: `sub.liafonx.net` A → `88.151.34.29`, DNS-only (grey cloud). The Cloudflare proxy carries only HTTP(S).
- Client links: only in MacBook `~/proxy-refactor/links/links.txt` (0600).
- `mini-exit` password: VPS `~/proxy-refactor/phase-8/state.json` (root). `phase-8/asspp-proxy-url` (liafonx, 0600)
  holds `socks5h://vps:<pass>@172.18.0.1:10810`. ASSPP (`assppweb-asspp-1`) uses it as `ASSPP_PROXY_URL=` in
  `~/AssppWeb/.env`.

## Clients (Shadowrocket)

- Use Shadowrocket 2.2.83 or later. 2.2.81 added VLESS Encryption, and 2.2.83 fixed Vision on it.
- Node settings: TLS off, transport none, flow `xtls-rprx-vision`, mux off, UDP relay on.
  With UDP relay on, Claude's QUIC goes to the node, the VPS blocks it, and the app falls back to TCP through the tunnel.
- Link form: `vless://<uuid>@sub.liafonx.net:8443?encryption=<client>&flow=xtls-rprx-vision&security=none&type=tcp#<name>`.
  A link is a bearer credential. Never print or commit one.
- To revoke a user, remove their UUID from `claude-vless`.

## Xray version: pinned to 26.9.30

- VPS: `/usr/local/bin/xray` (old binary kept as `xray.25.10.15`). Mini: manual keg `/usr/local/Cellar/xray/26.9.30`
  behind `/usr/local/opt/xray`, `brew pin`ned (Homebrew's "latest" is 26.3.27).
- The loopback harness (VPS `~/proxy-refactor/version_harness.py`) found: 26.3.27 ignores `finalRules`, 26.4.25 blocks
  reverse traffic with no override, 26.6.1 and 26.9.30 pass. Upstream marks every release since March as pre-release.
- From 26.4 on, Xray blocks traffic out of a reverse tunnel by default. So the Mini's `qb-local` and `direct-out` carry
  explicit `finalRules`. These rules see the rewritten redirect target.
- An older binary ignores `finalRules` without a warning. The apply scripts refuse that combination. They also refuse
  a new binary without `finalRules` on the Mini.
- Before any upgrade, run the harness again on both builds. Do not trust "Latest". Parse-test a config with
  `xray run -test -format json -config X.json` (the file needs a `.json` suffix).

## Security design

- The VPS does all destination filtering (owner decision). The Mini keeps only the `qb.invalid` redirect and the
  dial-time guard.
- The allow-list uses only `domain:` and `full:` entries on vendor names. `keyword:`, `regexp:` or geosite entries
  would also match lookalikes such as `datadog-evil.com`.
- `mini-exit` passes only Docker (172.16.0.0/12) and loopback sources. Other Docker ranges need a new rule. Any VPS
  container with the password can use it, and the owner accepts this.
- Claude and `mini-exit` traffic never uses `direct-out`, the VPS default outbound. Both rule sets end in `block`, so
  they fail closed when the tunnel is down.
- Blocked requests get the blackhole's `403` page. The SOCKS inbound replies "ok" before routing, so test the data flow.
- The marker `qb.invalid:54904` identifies qB's flow, never an IP. No inbound sniffs, because sniffing could let a
  request spoof the marker.
- qBittorrent is bound to `lo0` and leaves only through `127.0.0.1:10801`, so it cannot leak the Mini's IP.
- The incident that started this: a VPS HTTP inbound on 10803 had `"users"` instead of `"accounts"`. It ran with no
  authentication and was abused. Test any new HTTP or SOCKS inbound from outside with no and with wrong credentials.

## Changes and rollback

Scripts and snapshots live in `~/proxy-refactor/` on each host, not in this repo. Make each change as a phase:

1. Write a builder and a `stage-phase-N.sh` script.
2. Test the built config in a sandbox on the production binary.
3. The owner runs `sudo bash ~/proxy-refactor/stage-phase-N.sh && sudo bash ~/proxy-refactor/apply-phase.sh phase-N`.
4. Run the checks below.

`apply-phase.sh` takes a snapshot, parse-tests, installs, restarts and self-tests the public ports. On failure it rolls back.

- Rollback: `sudo bash ~/proxy-refactor/apply-phase.sh phase-N --rollback`. Guards refuse with exit 11 (the live
  config is not the one the phase installed) or exit 12 (a port that closes still has clients).
  `--rollback-force` skips both guards.
- Roll back the Mini first, then the VPS.
- VPS phases ran in the order 7a, 7, 8, 7b. Roll back in reverse: 7b → 8 → 7 → 7a.
- Before `phase-8 --rollback`, run `bash ~/proxy-refactor/switch-asspp.sh --rollback`. ASSPP then stays down, because
  its old URL uses 10802.
- Warning: `phase-7b --rollback` reopens SOCKS 10802 (`claude-in`).
- The Mini's emergency phases 6 and 7 are rolled back. Do not apply them again.

## Checks (read-only)

```bash
# VPS xray ports: 8443, 10810, 54451, 54904 (443 is Caddy). No 10802.
ssh liafonx@88.151.34.29 'ss -Htln'
# Mini: only 127.0.0.1.10801 listens.
ssh liafonx@Liafonxs-Mac-mini.local 'netstat -an -p tcp | grep LISTEN'
nc -z -w 5 88.151.34.29 10802   # from the MacBook: must fail
ssh liafonx@88.151.34.29 'ss -H -tn state established "( sport = :54451 )"'   # tunnel up

# 8443: on the Mini (/usr/local/opt/xray/bin/xray), run a 0600 client config built from the owner link (never print
# it): socks in 127.0.0.1:<p>, vless out with the link's values, streamSettings {network raw, security none}.
curl -s -o /dev/null -w '%{http_code}\n' --socks5-hostname 127.0.0.1:<p> https://api.anthropic.com  # any HTTP code
curl -s -m 10 --socks5-hostname 127.0.0.1:<p> http://example.com   # canned 403 page or no data

# 10810, on the VPS as liafonx. The password stays in a 0600 file, out of argv.
umask 077; f=$(mktemp)
printf 'proxy = "%s"\n' "$(sed 's/@172\.18\.0\.1:/@127.0.0.1:/' ~/proxy-refactor/phase-8/asspp-proxy-url)" > "$f"
curl -s -m 15 -K "$f" https://api.ipify.org; echo   # the Mini's public IP
rm -f "$f"   # with @88.151.34.29: instead, auth succeeds and no data comes back

# qB outbound exits from the VPS IP.
ssh liafonx@Liafonxs-Mac-mini.local 'curl -s --socks5-hostname 127.0.0.1:10801 https://api.ipify.org'
# qB inbound: hold a connection to VPS:54904. A new ESTABLISHED socket appears on qB's 127.0.0.1:54904 (lsof -p <qB pid>).
```

## Gotchas

- The hosts' login shell is zsh, and the Mini's `/bin/bash` is 3.2. Write scripts for both (no `BASHPID`, no `${a[-1]}`).
- `freedom.settings.domainStrategy` is deprecated in 26.x. The configs use `streamSettings.sockopt.domainStrategy`.
- Warning: do not turn on "Use proxy for peer connections" in qB's UI. A try on 2026-10-04 (21:03-21:09) bound qB to
  0.0.0.0. The setting also hurts incoming connectivity, which private-tracker seeding needs. qB has no outbound peers
  (`ProxyPeerConnections=false`). For outbound peers, use an OS-level transparent redirect.
- qB logged `SOCKS5 proxy error ... End of file` every 305 s. The default `connIdle` (300 s) closed its idle
  UDP-ASSOCIATE connection. The fix is live: `qb-socks` has `settings.userLevel: 1` with `policy.levels.1.connIdle: 86400`.
- UDP inbound (uTP) is on: VPS tunnel `network: "tcp,udp"`, Mini `qb-local` `finalRules` `tcp,udp`. Change both
  together, because a tcp-only rule drops UDP without a warning. To revert, set the VPS tunnel to `"tcp"`.
- UDP sent to VPS:54904 raises qB's received-bytes counter by the same bytes. qB ignores synthetic uTP probes, so only
  real peers show a round trip (inbound µTP in the peers list). Incoming TCP works for all 17 loaded torrents.
- The VPS has no explicit block rule for UUID-F traffic. By default, Xray 26.9.30 blocks loopback, private and
  reserved targets for VLESS-inbound traffic (live-tested). This does not cover the VPS's own public IP, which the
  internet reaches anyway.

## Disabled legacy (files left in place, inverse commands)

| What | Where | Re-enable |
|---|---|---|
| `realm` TLS relay (`com.example.realm` from `com.proxy.realm.plist`) | Mini, user domain | `launchctl enable gui/$(id -u)/com.example.realm && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.proxy.realm.plist` |
| `gost` (`com.gost.proxy`) | Mini, user domain | same pattern with `com.gost.proxy.plist` |
| `realm.service` | VPS | `sudo systemctl enable --now realm` |
| duplicate user-level `homebrew.mxcl.xray` agent | Mini | plist removed (identical to the root daemon's). The disable override stays, so `brew services start xray` as the user cannot recreate it |
