# Provisioning princess — end to end

Verified against the Linode API, Tailscale docs, and the freddy/sullivan
repos on 2026-07-06.

## 0. Prerequisites (already done)

All GitHub secrets are set on `nuniesmith/princess` — see
[GITHUB_SECRETS.md](GITHUB_SECRETS.md). One thing to confirm in the
[Tailscale admin console](https://login.tailscale.com/admin/settings/oauth):
the OAuth client (the one in `TAILSCALE_OAUTH_CLIENT_ID/SECRET`) needs the
**auth_keys** scope — it already has it if freddy/sullivan deploys work —
because provisioning uses its secret directly as the server's auth key.

## 1. Create the server (fully automated)

GitHub → Actions → **👑 Provision Princess (Linode)** → Run workflow → type
`princess` in the confirm box.

What it does:

1. Skips creation if a Linode labelled `princess` already exists (idempotent).
2. Derives the `actions` user's public key from the `SSH_KEY` secret and
   renders it into `provision/cloud-init.yaml`.
3. `POST /v4/linode/instances` — region `ca-central` (Toronto), type
   `g6-nanode-1`, image `linode/ubuntu26.04`, root key from `ROOT_SSH_KEY`,
   cloud-init as base64 `metadata.user_data`.
   ⚠️ user_data is **immutable after create** — bootstrap changes require a
   rebuild, which is why cloud-init stays minimal and everything else deploys
   over SSH.
4. Waits for `running`, SSHes as root, waits for `cloud-init status --wait`.
5. **Joins the tailnet**: `tailscale up` with the OAuth client secret as auth
   key (`?ephemeral=false&preauthorized=true`, `--advertise-tags=tag:ci`,
   `--accept-routes`, `--advertise-exit-node` unless unchecked). Tag-owned
   nodes have **no key expiry** — nothing to disable in the console.
6. Prints the Tailscale IP in the run summary.

Cloud-init gives you: `actions` (CI, docker group) + `jordan` (sudo) users,
hardened sshd (key-only, drop-in `99-princess-hardening.conf`), Docker CE with
freddy's hardened `daemon.json`, UFW (**22 + tailscale0 only — no public
80/443**), fail2ban, Tailscale installed, IP forwarding for exit-node duty.

## 2. One manual minute

1. Update the **`PRINCESS_TAILSCALE_IP`** repo secret with the IP from the run
   summary.
2. If you left exit-node on: approve it in the admin console
   (Machines → princess → Edit route settings → allow exit node).
3. If your tailnet uses ACLs (not default allow-all), make sure:
   - your devices → princess:443 (and :80),
   - princess (its tag) → freddy/sullivan service ports,
   - `tag:ci` → princess:22 (CI deploys over the tailnet).

## 3. First deploy

Push to `main` (or dispatch **👑 Princess Deploy**). The pipeline:

1. Runner joins the tailnet as an ephemeral `tag:ci` node
   (`tailscale-connect` composite, OAuth client).
2. First run: no cert in the `ssl-certs` volume → generates the wildcard
   Let's Encrypt cert (`7gram.xyz`, `*.7gram.xyz`, `*.sullivan.7gram.xyz`) via
   Cloudflare DNS-01 on the runner, scps the tarball over, extracts it into
   the volume.
3. Clones the repo to `/home/actions/princess`, generates `.env` on the server
   (`run.sh setup-env` auto-sets `BIND_IP` to the tailscale IP), builds and
   starts nginx **bound to the tailscale IP** — the public IP stays dark.

## 4. Verify BEFORE touching DNS

From a machine **on the tailnet** (nothing is reachable from outside it):

```bash
TS_IP=<princess tailscale ip>
curl -s  --resolve 7gram.xyz:443:$TS_IP        https://7gram.xyz/health      # OK
curl -sI --resolve nc.7gram.xyz:443:$TS_IP     https://nc.7gram.xyz/         # freddy
curl -sI --resolve sonarr.7gram.xyz:443:$TS_IP https://sonarr.7gram.xyz/     # sullivan
```

And confirm the public IP really is dark (from anywhere):

```bash
curl -m 5 http://<public-ip>/   # should time out / refuse
```

## 5. DNS cutover

See [CUTOVER.md](CUTOVER.md) — dispatch **👑 Princess Deploy** with
`update_dns=true`; records move to princess's tailscale IP.

## 6. Optional hardening

```bash
# Close public SSH once the tailnet SSH path works (Lish console = rescue):
sudo ufw delete allow 22/tcp
```

After this the Linode has **zero** publicly reachable ports.

## Costs

| Item | $ |
|---|---|
| Nanode 1GB, ca-central | $5.00/mo (hourly 0.0075) |
| Network transfer | 1 TB included |
| Backups (not enabled) | +$2/mo if wanted |

$20 credit ≈ 4 months.
