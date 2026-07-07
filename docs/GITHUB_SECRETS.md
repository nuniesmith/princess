# GitHub secrets — princess

Names follow the freddy convention. Three groups, by when they matter:

## Needed BEFORE provisioning (already set)

| Secret | Used by | Purpose |
|---|---|---|
| `LINODE_API_KEY` | provision.yml | Check for / create the Linode instance |
| `ROOT_PASSWORD` | provision.yml | The instance's root password (Linode `root_pass`) — your Lish-console rescue access. Linode enforces a strength check; use 12+ mixed chars |
| `TAILSCALE_OAUTH_CLIENT_ID` / `TAILSCALE_OAUTH_SECRET` | both workflows | (a) CI runners join the tailnet as ephemeral `tag:ci` nodes; (b) provision.yml uses the secret directly as princess's auth key (needs writable `auth_keys` scope + `tag:ci`) |
| `CLOUDFLARE_API_TOKEN` | ci-cd.yml | DNS-01 cert issuance + DNS record updates (Zone:DNS:Edit) |
| `CLOUDFLARE_ZONE_ID` | ci-cd.yml | The 7gram.xyz zone |
| `SSL_EMAIL` | ci-cd.yml | Let's Encrypt account email |
| `DISCORD_WEBHOOK_ACTIONS` | both workflows | Run notifications |

Provisioning needs **no SSH secrets**: the workflow generates a run-ephemeral
root key, injects it at create, and removes it from the server when done.

## Set by YOU right after provisioning (values generated ON the server)

The provision run summary prints these exact commands:

| Secret | Source on the server | Used by |
|---|---|---|
| `SSH_KEY` | `/home/actions/.ssh/id_ed25519` | ci-cd.yml — deploys as the `actions` user |
| `ROOT_SSH_KEY` | `/root/.ssh/id_ed25519` | nothing in CI today — your convention/rescue key |

```bash
ssh root@<public-ip> 'cat /home/actions/.ssh/id_ed25519' | gh secret set SSH_KEY -R nuniesmith/princess
ssh root@<public-ip> 'cat /root/.ssh/id_ed25519'         | gh secret set ROOT_SSH_KEY -R nuniesmith/princess
```

(`ssh root@…` works with your desktop key — cloud-init adds it to root; the
private keys never appear in workflow logs since this repo is public.)

## Optional

| Secret | Default behaviour without it | Why you'd set it |
|---|---|---|
| `PRINCESS_TAILSCALE_IP` | deploy + DNS jobs discover princess on the tailnet by hostname | Pin the IP explicitly; any non-`100.x` value (e.g. a placeholder) is ignored |
| `SSH_USER` | `actions` | Different CI user |
| `SSH_PORT` | `22` | Non-standard sshd port |
| `FREDDY_TAILSCALE_IP` | baked default `100.106.65.55` | If freddy's tailnet IP changes |
| `SULLIVAN_TAILSCALE_IP` | baked default `100.87.125.19` | If sullivan's tailnet IP changes |

App secrets (`PHOTOPRISM_*`, `NEXTCLOUD_*`, `AUTHENTIK_*`, …) stay in the
freddy repo — princess only proxies; it holds no application credentials
beyond TLS certs.
