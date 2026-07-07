# Provisioning princess — end to end

Verified against the Linode API, Tailscale docs, and the freddy/sullivan
repos on 2026-07-06.

## The order of operations

```
you: dispatch provision ──► Linode API: "princess" exists?
                                 │no                 │yes → report IPs, done
                                 ▼
                          create instance (root_pass = ROOT_PASSWORD,
                          run-ephemeral root key, cloud-init user_data)
                                 ▼
                          wait running → root SSH → cloud-init finishes
                          (update+upgrade, users, sshd hardening, docker,
                           ufw 22+tailscale0 only, fail2ban, tailscale pkg)
                                 ▼
                          tailscale up (OAuth secret as auth key,
                          tag-owned → no key expiry, exit node)
                                 ▼
                          generate SSH keypairs ON the server
                          (root + actions) → revoke ephemeral key
                                 ▼
you: copy the 2 generated keys into GH secrets (one-liner each)
you: approve exit node in the Tailscale console
you: dispatch deploy → done (it finds princess on the tailnet itself)
```

## 1. Dispatch the provision workflow

GitHub → Actions → **👑 Provision Princess (Linode)** → Run workflow → type
`princess` in the confirm box. Prereqs are just `LINODE_API_KEY`,
`ROOT_PASSWORD`, and the Tailscale OAuth secrets —
**no SSH key secrets are needed to provision** (a run-ephemeral key handles
the bootstrap and is removed from the server at the end).

Instance: region `ca-central` (Toronto), type `g6-nanode-1` ($5/mo), image
`linode/ubuntu26.04`. ⚠️ cloud-init `user_data` is immutable after create —
bootstrap changes require a rebuild; everything else deploys over SSH.

## 2. Copy the two server-generated secrets (~1 minute)

The run summary prints these with the real IP filled in:

```bash
ssh root@<public-ip> 'cat /home/actions/.ssh/id_ed25519' | gh secret set SSH_KEY -R nuniesmith/princess
ssh root@<public-ip> 'cat /root/.ssh/id_ed25519'         | gh secret set ROOT_SSH_KEY -R nuniesmith/princess
```

Root SSH works with your desktop key (cloud-init installs it for both `jordan`
and `root`); Lish console + `ROOT_PASSWORD` is the backup path. The keys are
generated on the server and never pass through workflow logs.

Also: approve the **exit node** in the
[Tailscale admin console](https://login.tailscale.com/admin/machines)
(Machines → princess → Edit route settings). Tag-owned nodes have no key
expiry — nothing to disable.

If your tailnet uses ACLs (not default allow-all), ensure: your devices →
princess:443/80; princess (its tag) → freddy/sullivan service ports;
`tag:ci` → princess:22.

## 3. First deploy

Push to `main` or dispatch **👑 Princess Deploy**:

1. Runner joins the tailnet (ephemeral `tag:ci`) and **discovers princess by
   hostname** — no IP secret required (`PRINCESS_TAILSCALE_IP` is an optional
   override).
2. First run: empty `ssl-certs` volume → wildcard Let's Encrypt cert
   (`7gram.xyz`, `*.7gram.xyz`, `*.sullivan.7gram.xyz`) via Cloudflare DNS-01
   on the runner, shipped into the volume. Renewed by the weekly cron when
   <30 days remain (or if a non-LE cert is ever found).
3. Repo cloned to `/home/actions/princess`, `.env` generated on the server
   (`run.sh setup-env` auto-sets `BIND_IP` to the tailscale IP), nginx built
   and started **bound to the tailscale IP** — the public IP stays dark.

## 4. Verify BEFORE touching DNS

From a machine **on the tailnet**:

```bash
TS_IP=$(tailscale ip -4 princess)
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
`update_dns=true`; records move to princess's tailscale IP (auto-resolved).

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
