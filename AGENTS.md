# AGENTS.md — princess

Deployment repo for **princess**, the $5/mo Linode edge server for `7gram.xyz`: Cloudflare DNS, nginx TLS termination, and the Tailscale entry point. It reverse-proxies every `*.7gram.xyz` service over the tailnet to the home servers (freddy 100.106.65.55, sullivan 100.87.125.19, oryx 100.113.72.63).

## Shared context

Read the shared agent context first: `soul.md` and `memory.md` (especially §1) in the [agents repo](https://github.com/nuniesmith/agents).

## How nginx is laid out

- Upstreams are `map $host $<name>_upstream` variables in `services/nginx/nginx.conf`.
- Server blocks live in `services/nginx/conf.d/`: `10-freddy-services.conf`, `20-sullivan-services.conf`, `30-oryx-services.conf`. Put a new service in its host's file.
- A "👑 Princess Deploy" workflow runs on merge to main; Markdown and `docs/**` are `paths-ignore`d.

## Rules

- **Nothing on `7gram.xyz` is public.** The DNS records are public, but every name is reachable only from a device on the tailnet. Never describe a 7gram service as publicly exposed, and don't "fix" that.
- Adding a subdomain is a three-part change: DNS (Cloudflare), the server block here, and the service actually listening on the target host. Verify end-to-end with curl over the tailnet afterwards.
- Old subdomains get a wholesale 301 redirect to their replacement (the shelfmark → managarr pattern), preserving `$request_uri`.
- Cert renewal is weekly via `ci-cd.yml`, kept alive by the host-update workflow (11:41 UTC). A silent princess is a finding, not a relief.
