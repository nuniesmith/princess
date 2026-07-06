# DNS cutover: freddy → princess

Today `7gram.xyz` + `*.7gram.xyz` A records point at **freddy's Tailscale IP**
(proxied=false) — the domain only works from inside the tailnet. The cutover
re-points those records at **princess's Tailscale IP**. The access model does
not change: clients still need Tailscale to load anything. What changes is
which nginx answers — princess terminates TLS in Toronto and proxies over the
tailnet to freddy/sullivan.

## Pre-flight checklist

1. Princess is deployed and healthy (deploy workflow green, Discord ✅).
2. From a machine **on the tailnet**, spot-check services against princess's
   tailscale IP before touching DNS:

   ```bash
   TS_IP=<princess tailscale ip>
   curl -s  --resolve 7gram.xyz:443:$TS_IP        https://7gram.xyz/health
   curl -sI --resolve nc.7gram.xyz:443:$TS_IP     https://nc.7gram.xyz/       # freddy backend
   curl -sI --resolve sonarr.7gram.xyz:443:$TS_IP https://sonarr.7gram.xyz/   # sullivan backend
   ```

3. Real wildcard cert installed (not the self-signed fallback):

   ```bash
   echo | openssl s_client -connect $TS_IP:443 -servername 7gram.xyz 2>/dev/null \
     | openssl x509 -noout -issuer     # expect Let's Encrypt
   ```

4. **Freddy-side proxy trust** — after cutover the proxy hitting the backends
   is princess (source = its tailscale IP), not freddy's local nginx:
   - **Home Assistant** hard-fails (400) on untrusted `X-Forwarded-For`
     senders: add princess's tailscale IP (or `100.64.0.0/10`) to
     `http: trusted_proxies:` in HA's configuration.yaml on freddy + restart.
   - **Nextcloud**: add the same to `trusted_proxies` in config.php (soft
     failure only — client IPs would be misattributed otherwise).

## Cutover

GitHub → Actions → **👑 Princess Deploy** → Run workflow → check
**update_dns**. The job upserts `7gram.xyz` + `*.7gram.xyz` A records to
`PRINCESS_TAILSCALE_IP` (ttl auto, proxied=false — Cloudflare cannot reach
CGNAT IPs, so the orange cloud is not an option in this model).

Propagation is minutes (ttl=auto). Freddy's nginx keeps running throughout —
nothing breaks mid-flip; devices just start landing on princess.

## After cutover

- Disable/ignore freddy's `dns-update` job so a freddy deploy doesn't point
  the domain back at freddy.
- Freddy's nginx can be retired whenever convenient — princess doesn't need it.
- Freddy's weekly SSL-renewal cron becomes princess's job (already in
  ci-cd.yml); turn freddy's off to avoid duplicate cert issuance.

## Rollback

Run **freddy's** workflow with its `update_dns` input — records go back to
`FREDDY_TAILSCALE_IP`. Nothing is deleted in either direction.
