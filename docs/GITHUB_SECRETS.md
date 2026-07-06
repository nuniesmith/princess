# GitHub secrets — princess

All set on `nuniesmith/princess` (2026-07-06). Names follow the freddy
convention (`SSH_KEY`, not sullivan's `SULLIVAN_SSH_KEY` style).

| Secret | Used by | Purpose |
|---|---|---|
| `LINODE_API_KEY` | provision.yml, ci-cd.yml (dns job) | Create/inspect the Linode instance |
| `ROOT_SSH_KEY` | provision.yml | Private key whose pubkey becomes root's `authorized_keys`; used once to watch cloud-init finish |
| `SSH_KEY` | ci-cd.yml | Private key for the `actions` CI user (pubkey derived and installed by cloud-init) |
| `SSH_USER` | ci-cd.yml | Falls back to `actions` |
| `SSH_PORT` | ci-cd.yml | Falls back to `22` |
| `PRINCESS_TAILSCALE_IP` | ci-cd.yml | Deploy target AND the DNS record content (tailnet-only access) — **update after provisioning** (the provision run summary prints it) |
| `TAILSCALE_OAUTH_CLIENT_ID` / `TAILSCALE_OAUTH_SECRET` | both workflows | (a) runner joins the tailnet as ephemeral `tag:ci` node; (b) provision.yml uses the secret directly as the server's auth key (needs writable `auth_keys` scope + `tag:ci`) |
| `CLOUDFLARE_API_TOKEN` | ci-cd.yml | DNS-01 cert issuance + DNS record updates (needs Zone:DNS:Edit) |
| `CLOUDFLARE_ZONE_ID` | ci-cd.yml | The 7gram.xyz zone |
| `SSL_EMAIL` | ci-cd.yml | Let's Encrypt account email |
| `DISCORD_WEBHOOK_ACTIONS` | both workflows | Deploy/provision notifications |

## Optional additions (defaults are baked into the repo)

| Secret | Default | Why you'd set it |
|---|---|---|
| `FREDDY_TAILSCALE_IP` | `100.106.65.55` | If freddy's tailnet IP ever changes |
| `SULLIVAN_TAILSCALE_IP` | `100.87.125.19` | If sullivan's tailnet IP ever changes |

When set, the deploy job seds them into the server's `.env`, and the nginx
entrypoint rewrites the upstream maps at container start.

## Not used here (freddy-only)

App secrets like `PHOTOPRISM_*`, `NEXTCLOUD_*`, `AUTHENTIK_*` stay in the
freddy repo — princess only proxies; it holds no application state or
credentials beyond TLS certs.
