#!/usr/bin/env bash
# princess — edge server helper (lean version of freddy's run.sh).
set -euo pipefail

cd "$(dirname "$0")"

ensure_key() {
    # ensure_key KEY DEFAULT — add KEY=DEFAULT to .env if the key is missing.
    local key="$1" default="$2"
    grep -qE "^${key}=" .env 2>/dev/null || echo "${key}=${default}" >> .env
}

cmd_setup_env() {
    touch .env
    ensure_key TZ "America/Toronto"
    ensure_key SSL_DOMAIN "7gram.xyz"
    ensure_key FREDDY_TAILSCALE_IP "100.106.65.55"
    ensure_key SULLIVAN_TAILSCALE_IP "100.87.125.19"

    # Tailnet-only: bind nginx to this host's Tailscale IP. Re-detected on
    # every setup-env so the value heals itself once tailscale is up.
    local ts_ip
    ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    if [ -n "$ts_ip" ]; then
        if grep -qE "^BIND_IP=" .env; then
            sed -i "s|^BIND_IP=.*|BIND_IP=${ts_ip}|" .env
        else
            echo "BIND_IP=${ts_ip}" >> .env
        fi
        echo "BIND_IP=${ts_ip} (tailscale)"
    else
        ensure_key BIND_IP "127.0.0.1"
        echo "⚠️  tailscale not up — BIND_IP left/defaulted to 127.0.0.1"
    fi

    chmod 600 .env
    echo "✅ .env ready"
}

cmd_start() {
    docker volume inspect ssl-certs >/dev/null 2>&1 || docker volume create ssl-certs
    docker compose up -d --build
}

cmd_stop()    { docker compose down --remove-orphans; }
cmd_restart() { cmd_stop; cmd_start; }
cmd_logs()    { docker compose logs -f "${1:-nginx}"; }
cmd_status()  { docker compose ps; }

cmd_health() {
    curl -sf http://localhost/health && echo "HTTP  ✅"
    # Host header needed: the HTTPS default server drops unknown hosts (444)
    curl -skf -H "Host: ${SSL_DOMAIN:-7gram.xyz}" https://localhost/health && echo "HTTPS ✅"
    echo "cert:"
    echo | openssl s_client -connect localhost:443 -servername "${SSL_DOMAIN:-7gram.xyz}" 2>/dev/null \
        | openssl x509 -noout -subject -issuer -enddate
}

case "${1:-}" in
    setup-env) cmd_setup_env ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    logs)      shift || true; cmd_logs "$@" ;;
    status)    cmd_status ;;
    health)    cmd_health ;;
    *)
        echo "usage: $0 {setup-env|start|stop|restart|logs [svc]|status|health}"
        exit 1
        ;;
esac
