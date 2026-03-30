#!/usr/bin/env bash
set -euo pipefail

# ─── Step 1: OS/arch guard ────────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

if [[ "$OS" != "Linux" || "$ARCH" != "x86_64" ]]; then
  echo "ERROR: This script is for Ubuntu/Debian amd64 only."
  echo "Current: ${OS}/${ARCH}"
  exit 1
fi

# ─── Step 2: Interactive prompts ──────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo "  ntfy Server Setup (Caddy + acme.sh)"
echo "═══════════════════════════════════════════"
echo ""

read -rp "ntfy subdomain (e.g. ntfy.liafonx.net): " NTFY_DOMAIN
read -rp "Notification topic (e.g. claude-liafonx-abc123): " NTFY_TOPIC
read -rp "Local listen port for ntfy [2586]: " NTFY_PORT_INPUT
NTFY_PORT="${NTFY_PORT_INPUT:-2586}"

read -rp "Enable authentication? (y/N): " AUTH_ENABLED_INPUT
AUTH_ENABLED="${AUTH_ENABLED_INPUT:-N}"
AUTH_ENABLED="${AUTH_ENABLED,,}"

NTFY_USER=""
if [[ "$AUTH_ENABLED" == "y" ]]; then
  read -rp "Admin username: " NTFY_USER
fi

# ─── Step 3: Install ntfy ────────────────────────────────────────────────────

echo ""
echo "[1/7] Installing ntfy..."

sudo apt-get install -y curl gpg >/dev/null 2>&1

if [[ ! -f /etc/apt/sources.list.d/heckel.list ]]; then
  curl -fsSL https://archive.heckel.io/apt/pubkey.txt \
    | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/heckel.gpg
  sudo sh -c "echo 'deb [arch=amd64] https://archive.heckel.io/apt debian main' > /etc/apt/sources.list.d/heckel.list"
  sudo apt-get update >/dev/null 2>&1
fi

if ! sudo apt-get install -y ntfy; then
  echo "ERROR: ntfy installation failed."
  echo "Install manually: https://docs.ntfy.sh/install/"
  exit 1
fi

echo "  ntfy installed."

# ─── Step 4: Write /etc/ntfy/server.yml ──────────────────────────────────────
# ntfy listens on localhost only — Caddy handles TLS on :443

echo "[2/7] Writing /etc/ntfy/server.yml..."

sudo mkdir -p /etc/ntfy

if [[ "$AUTH_ENABLED" == "y" ]]; then
  sudo tee /etc/ntfy/server.yml > /dev/null <<EOF
base-url: "https://${NTFY_DOMAIN}"
listen-http: "127.0.0.1:${NTFY_PORT}"
behind-proxy: true
auth-default-access: "deny-all"
auth-file: "/var/lib/ntfy/user.db"
EOF
else
  sudo tee /etc/ntfy/server.yml > /dev/null <<EOF
base-url: "https://${NTFY_DOMAIN}"
listen-http: "127.0.0.1:${NTFY_PORT}"
behind-proxy: true
EOF
fi

echo "  server.yml written (listening on 127.0.0.1:${NTFY_PORT})."

echo "[3/7] Auth user creation deferred until after ntfy starts."

# ─── Step 5: Issue TLS cert via acme.sh ──────────────────────────────────────
# Matches existing pattern: dns_cf validation, EC-256, install to /etc/caddy/certs/

ACME_SH="$HOME/.acme.sh/acme.sh"
CERT_DIR="/etc/caddy/certs/${NTFY_DOMAIN}"

echo "[4/7] Issuing TLS certificate for ${NTFY_DOMAIN}..."

if [[ ! -f "$ACME_SH" ]]; then
  echo "ERROR: acme.sh not found at $ACME_SH"
  exit 1
fi

# dns_cf needs CF_Token in the environment
if [[ -z "${CF_Token:-}" ]]; then
  echo "  CF_Token not found in environment."
  read -rp "  Enter your Cloudflare API token: " CF_Token
  export CF_Token
fi

if [[ ! -d "$HOME/.acme.sh/${NTFY_DOMAIN}_ecc" ]]; then
  "$ACME_SH" --issue --dns dns_cf -d "$NTFY_DOMAIN" --keylength ec-256
else
  echo "  Certificate already issued, skipping."
fi

# Install cert to Caddy certs dir — owned by liafonx:caddy (matches sub.liafonx.net pattern)
sudo mkdir -p "$CERT_DIR"
sudo chown "$(whoami):caddy" "$CERT_DIR"
sudo chmod 750 "$CERT_DIR"

"$ACME_SH" --install-cert -d "$NTFY_DOMAIN" --ecc \
  --key-file       "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --reloadcmd      "sudo -n systemctl reload caddy"

echo "  Certificate installed to ${CERT_DIR}/"

# ─── Step 7: Write Caddy site config ─────────────────────────────────────────

CADDY_SITE="/etc/caddy/sites-available/${NTFY_DOMAIN}.caddy"

echo "[5/7] Writing Caddy config at ${CADDY_SITE}..."

sudo tee "$CADDY_SITE" > /dev/null <<EOF
${NTFY_DOMAIN} {
    tls ${CERT_DIR}/fullchain.pem ${CERT_DIR}/privkey.pem

    # ntfy uses Server-Sent Events and WebSockets for subscriptions
    @streaming {
        path /*/ws /*/sse /*/json
    }

    handle @streaming {
        reverse_proxy 127.0.0.1:${NTFY_PORT} {
            flush_interval -1
        }
    }

    handle {
        encode zstd gzip
        reverse_proxy 127.0.0.1:${NTFY_PORT}
    }

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options    "nosniff"
        X-Frame-Options           "DENY"
        Referrer-Policy           "strict-origin-when-cross-origin"
        -X-Powered-By
        -Server
    }

    log {
        output file /var/log/caddy/ntfy_access.log
        format json
    }
}
EOF

echo "  Caddy site config written."

# ─── Step 8: Enable + start services ─────────────────────────────────────────

echo "[6/7] Starting services..."

sudo systemctl enable ntfy
sudo systemctl restart ntfy
sleep 2

# Reload Caddy to pick up the new site config (Caddyfile imports sites-available/*.caddy)
sudo systemctl reload caddy

echo "  ntfy started, Caddy reloaded."

# ─── Step 6b: Create auth user (now that ntfy has started and created the db) ─

if [[ "$AUTH_ENABLED" == "y" ]]; then
  echo ""
  echo "Creating admin user '${NTFY_USER}'..."
  sudo ntfy user add --role=admin "$NTFY_USER"
  echo "  User created. Generate a token: sudo ntfy token add ${NTFY_USER}"
fi

# ─── Step 9: Smoke tests ─────────────────────────────────────────────────────

echo "[7/7] Running smoke tests..."

# Local health (direct to ntfy)
if curl -sf "http://127.0.0.1:${NTFY_PORT}/v1/health" > /dev/null; then
  echo "  ✓ ntfy local health check passed"
else
  echo "  ✗ ntfy local health check FAILED"
fi

# HTTPS health (through Caddy)
if curl -sf "https://${NTFY_DOMAIN}/v1/health" > /dev/null; then
  echo "  ✓ HTTPS health check passed (https://${NTFY_DOMAIN})"
else
  echo "  ✗ HTTPS health check FAILED — DNS may not have propagated yet"
  echo "    Try: curl -sf https://${NTFY_DOMAIN}/v1/health"
fi

# POST test (skip if auth — no token yet)
if [[ "$AUTH_ENABLED" == "y" ]]; then
  echo "  ⊘ Skipping POST test (auth enabled). Generate a token first:"
  echo "    sudo ntfy token add ${NTFY_USER}"
else
  if curl -sf -X POST "http://127.0.0.1:${NTFY_PORT}/${NTFY_TOPIC}" -d "ntfy setup test" > /dev/null; then
    echo "  ✓ POST test passed"
  else
    echo "  ✗ POST test FAILED"
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo "  ntfy server setup complete!"
echo "═══════════════════════════════════════════"
echo ""
echo "Add these to ~/.zshenv on ALL machines (MacBook, Mac Mini, this server):"
echo ""
echo "  export NTFY_URL=\"https://${NTFY_DOMAIN}\""
echo "  export NTFY_TOPIC=\"${NTFY_TOPIC}\""
if [[ "$AUTH_ENABLED" == "y" ]]; then
  echo "  export NTFY_TOKEN=\"<your-token>\"  # generate with: sudo ntfy token add ${NTFY_USER}"
fi
echo ""
echo "Architecture:"
echo "  phone/curl → https://${NTFY_DOMAIN}:443 (Caddy) → 127.0.0.1:${NTFY_PORT} (ntfy)"
echo ""
echo "Cert auto-renewal: acme.sh cron issues + installs cert, reloads Caddy automatically."
echo ""
echo "Mobile app:"
echo "  1. Install ntfy app (iOS/Android)"
echo "  2. Server URL: https://${NTFY_DOMAIN}"
echo "  3. Subscribe to topic: ${NTFY_TOPIC}"
echo ""
