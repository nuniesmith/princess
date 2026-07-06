#!/bin/sh
# /docker-entrypoint.d/99-init.sh — runs before nginx starts (nginx:alpine hook).
#
# 1. Rewrites the baked-in backend tailnet IPs to the FREDDY_TAILSCALE_IP /
#    SULLIVAN_TAILSCALE_IP env values (defaults match, so this is a no-op
#    unless the IPs change).
# 2. Installs TLS certs from the ssl-certs volume (mounted read-only at
#    /etc/letsencrypt-volume, populated by CI), verifying the cert/key pair.
#    Falls back to the baked-in self-signed cert so nginx always starts.
set -e

DOMAIN="${SSL_DOMAIN:-7gram.xyz}"
TARGET_DIR="/etc/nginx/ssl"
FALLBACK_DIR="$TARGET_DIR/fallback"
VOLUME_DIR="/etc/letsencrypt-volume"

# Baked-in defaults these IPs were written with (see services/nginx/nginx.conf)
FREDDY_DEFAULT="100.106.65.55"
SULLIVAN_DEFAULT="100.87.125.19"

log() { echo "[99-init] $*"; }

# ── 1. Backend IP substitution ──────────────────────────────────────────────
substitute_ip() {
    default_ip="$1"; new_ip="$2"; name="$3"
    if [ -n "$new_ip" ] && [ "$new_ip" != "$default_ip" ]; then
        escaped=$(echo "$default_ip" | sed 's/\./\\./g')
        sed -i "s/$escaped/$new_ip/g" /etc/nginx/nginx.conf
        log "rewrote $name upstreams: $default_ip -> $new_ip"
    fi
}
substitute_ip "$FREDDY_DEFAULT" "$FREDDY_TAILSCALE_IP" "freddy"
substitute_ip "$SULLIVAN_DEFAULT" "$SULLIVAN_TAILSCALE_IP" "sullivan"

# ── 2. TLS certificates ─────────────────────────────────────────────────────
mkdir -p "$TARGET_DIR" /var/www/certbot

install_pair() {
    src_cert="$1"; src_key="$2"; origin="$3"
    # cert/key must be a matching pair
    cert_pub=$(openssl x509 -noout -pubkey -in "$src_cert" 2>/dev/null | openssl sha256 2>/dev/null) || return 1
    key_pub=$(openssl pkey -pubout -in "$src_key" 2>/dev/null | openssl sha256 2>/dev/null) || return 1
    if [ -n "$cert_pub" ] && [ "$cert_pub" = "$key_pub" ]; then
        cp "$src_cert" "$TARGET_DIR/fullchain.pem"
        cp "$src_key" "$TARGET_DIR/privkey.pem"
        chmod 600 "$TARGET_DIR/privkey.pem"
        log "installed certs from $origin"
        return 0
    fi
    log "WARNING: cert/key mismatch in $origin — skipping"
    return 1
}

installed=""
# Preferred: letsencrypt live layout from the CI-managed volume
if [ -f "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" ] && [ -f "$VOLUME_DIR/live/$DOMAIN/privkey.pem" ]; then
    install_pair "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" "$VOLUME_DIR/live/$DOMAIN/privkey.pem" \
        "ssl-certs volume (live/$DOMAIN)" && installed=1
fi
# Alternate: flat layout at the volume root
if [ -z "$installed" ] && [ -f "$VOLUME_DIR/fullchain.pem" ] && [ -f "$VOLUME_DIR/privkey.pem" ]; then
    install_pair "$VOLUME_DIR/fullchain.pem" "$VOLUME_DIR/privkey.pem" \
        "ssl-certs volume (flat)" && installed=1
fi
# Fallback: baked-in self-signed
if [ -z "$installed" ]; then
    cp "$FALLBACK_DIR/fullchain.pem" "$TARGET_DIR/fullchain.pem"
    cp "$FALLBACK_DIR/privkey.pem" "$TARGET_DIR/privkey.pem"
    chmod 600 "$TARGET_DIR/privkey.pem"
    log "WARNING: using baked-in SELF-SIGNED fallback cert (no certs in volume yet)"
fi

# ── 3. Validate before nginx takes over ─────────────────────────────────────
nginx -t
log "init complete"
