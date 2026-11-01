# SilverBullet

- [Service and pinned image](default.nix)
- [Routes](routes.nix)
- [Public DNS](../../../../terraform/dns.tf), [admin DNS](../../../../terraform/modules/netbird-access/main.tf)
- [Upstream docs](https://silverbullet.md)

Notes at `txt.pvlv.ca`, behind Cloudflare and Traefik. Server administration
(`/.setup`, `/.dashboard`, central login) is reachable only at
`txt.vpn.denys.me` over NetBird. Spaces use SilverBullet accounts; there is no
auth proxy. Customization lives in each space (`CONFIG`, Space Lua, Space
Style, libraries), not here.

## First deploy

1. Apply DNS, then `direnv exec . deploy .#chunkymonkey`.
2. Over NetBird, open `https://txt.vpn.denys.me/` and complete the setup
   wizard. Bind spaces to `txt.pvlv.ca`; bind the shared space to `/`, since
   the unbound root redirects to the private dashboard.
3. **Admin → Server**: set the primary URL to `https://txt.vpn.denys.me`.
4. Add accounts and grant each space access. Keep anonymous access `none`.

Optional: per space, connect a private Git repository under revisions for an
off-site copy.

## Limits

- The public router rejects encoded `/` and `\` in paths, so public page
  names cannot contain `\`.
- Account settings and password changes need the dashboard, so only over
  NetBird.
- Publicly, the space proxy (`net.proxyFetch`) reaches HTTPS hostnames such
  as GitHub, not IP or `localhost` targets. Redirects are still followed, but
  only without credentials, so they cannot use the dashboard.
- Write access runs Space Lua in other members' browsers. Grant it only to
  trusted people.
- The nightly backup stops the server while it archives the data folder.
  Clients keep working offline and sync after it restarts.

## Upgrade

After an image bump, deploy, then reload clients twice.
