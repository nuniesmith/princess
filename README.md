# 👑 princess

Standalone **edge server** for `7gram.xyz`: a $5/mo Linode Nanode in Toronto
(Ubuntu 26.04 LTS) that owns Cloudflare DNS, nginx TLS termination, and the
Tailscale entry point — and proxies every service over the tailnet to the
home servers:

- **freddy** (`100.106.65.55`) — Nextcloud, PhotoPrism, Home Assistant,
  Audiobookshelf, Authentik, Uptime Kuma
- **sullivan** (`100.87.125.19`) — Emby, Jellyfin, Plex, the *arr stack,
  qBittorrent, Tdarr, Mealie, Grocy, Wiki.js, …

**Access model: tailnet-only** (same as freddy's edge today). DNS records
point at princess's **Tailscale IP**, and nginx binds to the tailscale
interface — a client must be logged into the tailnet to load anything. The
Linode's public IP serves nothing (SSH only, until you close it). Princess
also advertises as a Tailscale **exit node**.

```
 your devices (on the tailnet)
      │  DNS: 7gram.xyz, *.7gram.xyz → 100.x (princess tailscale IP)
      ▼
┌──── princess (Linode, Toronto) ─────┐     public IP: dark
│ nginx :80/:443 bound to tailscale IP│     (nothing listens)
│ TLS: LE wildcard (DNS-01)           │
│ tailscaled --advertise-exit-node    │
└─────────┬──────────────┬────────────┘
   tailnet│              │tailnet
          ▼              ▼
      freddy          sullivan
  (home services)  (media services)
```

## How it deploys (same pattern as freddy/sullivan)

- **`.github/workflows/provision.yml`** — one-time, idempotent: checks Linode
  for an existing `princess` first; otherwise creates it (`ca-central` /
  `g6-nanode-1` / `linode/ubuntu26.04`, root password from the
  `ROOT_PASSWORD` secret so Lish access always works), bootstraps via
  cloud-init (users, sshd hardening, Docker, UFW, fail2ban), **joins the
  tailnet automatically** (OAuth client secret as auth key — tag-owned, no
  key expiry, no browser step), and **generates the permanent SSH keypairs on
  the server**. Needs no SSH secrets to run — a run-ephemeral key bootstraps
  root and is revoked at the end. You then copy the two generated keys into
  the `SSH_KEY` / `ROOT_SSH_KEY` secrets (one-liners in the run summary).
- **`.github/workflows/ci-cd.yml`** — on push: the runner joins the tailnet
  (ephemeral `tag:ci` node), **discovers princess by hostname** (no IP secret
  needed), renews the wildcard Let's Encrypt cert when <30 days remain
  (Cloudflare DNS-01, shipped into the `ssl-certs` Docker volume), git-pulls
  the repo on the server, and `docker compose up`s nginx.
  **DNS cutover is never automatic** — dispatch the workflow with
  `update_dns=true` when ready (see [docs/CUTOVER.md](docs/CUTOVER.md)).

Full bring-up: [docs/PROVISIONING.md](docs/PROVISIONING.md).
Secrets reference: [docs/GITHUB_SECRETS.md](docs/GITHUB_SECRETS.md).

## Repo layout

```
docker-compose.yml            nginx edge (single service, ssl-certs volume)
docker/nginx/                 image: config baked in, cert-fallback entrypoint
services/nginx/nginx.conf     upstream maps (tailnet IPs), resolver, rate zones
services/nginx/conf.d/        00-default, 10-freddy-services, 20-sullivan-services
services/nginx/dashboard/     static landing page at 7gram.xyz
provision/cloud-init.yaml     server bootstrap (rendered by provision.yml)
run.sh                        setup-env | start | stop | logs | status | health
```

## Why the tailnet-only design looks the way it does

- **nginx binds to the Tailscale IP** (`BIND_IP` in `.env`, auto-detected by
  `run.sh setup-env` from `tailscale ip -4`). This — not UFW — is the access
  control: Docker-published ports bypass UFW's rules, so firewalling alone
  would silently leave the public IP open.
- DNS `proxied=false` (grey cloud) is **required**: Cloudflare cannot reach
  CGNAT `100.x` addresses. Same as freddy's records today.
- The Tailscale **ACL** must allow: your devices → princess:443, princess →
  freddy/sullivan service ports, and `tag:ci` → princess:22 (CI deploys).
  A default allow-all tailnet already satisfies all three.

## Notes / deliberate changes vs freddy's edge

- All upstreams cross the tailnet (freddy's edge used `172.17.0.1` for its
  local services; that pattern is meaningless here).
- **jellyfin** upstream fixed: freddy pointed at `:8920` (emby's HTTPS port);
  sullivan actually publishes Jellyfin on host port `8097`.
- **wiki** upstream fixed: freddy pointed at `:3000`; sullivan publishes
  Wiki.js on host port `8090`.
- The HTTPS **default server is the 444 catch-all** (unknown hosts get
  dropped); on freddy the dashboard block silently absorbed them.
- Backend IPs are env-driven (`FREDDY_TAILSCALE_IP` / `SULLIVAN_TAILSCALE_IP`
  in `.env`); the container entrypoint rewrites the nginx maps at startup.

## The only manual steps

After the provision workflow finishes (commands with the real IP are in its
run summary):

```bash
ssh root@<public-ip> 'cat /home/actions/.ssh/id_ed25519' | gh secret set SSH_KEY -R nuniesmith/princess
ssh root@<public-ip> 'cat /root/.ssh/id_ed25519'         | gh secret set ROOT_SSH_KEY -R nuniesmith/princess
```

…and approve the exit node in the Tailscale admin console. That's it — the
deploy workflow finds princess on the tailnet by itself, so
`PRINCESS_TAILSCALE_IP` never has to be set (it's an optional override).
