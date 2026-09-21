# Paseo Relay

- [Service and pinned source](default.nix)
- [DNS records](../../../../terraform/dns.tf)
- [Source fork](https://github.com/meatcar/paseo-relay)

Hosted on chunkymonkey behind Cloudflare and Traefik. Keep DNS proxied;
the origin firewall admits Cloudflare traffic, not direct client connections.

## Deploy

Update the source revision and hash in `default.nix`, then run from the repo root:

```sh
direnv exec . deploy .#chunkymonkey
```

Quadlet builds the upstream Dockerfile on ARM64. Restarts disconnect active
sockets; clients must reconnect. After deployment, check `/health` and `/ready`,
then verify paired traffic in both directions and reconnects.

## Clients

```text
PASEO_RELAY_ENABLED=true
PASEO_RELAY_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_PUBLIC_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_USE_TLS=true
PASEO_RELAY_PUBLIC_USE_TLS=true
```

Changing the endpoint requires a new pairing offer. To use the upstream relay,
set both endpoints to `relay.paseo.sh:443` and keep TLS enabled.
