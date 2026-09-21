# Paseo Relay

- [Service and pinned source](../../nixos/modules/quadlets/paseo-relay/default.nix)
- [DNS records](../../terraform/dns.tf)
- [Source fork](https://github.com/meatcar/paseo-relay)

Runs on chunkymonkey as a rootless Podman service. Cloudflare proxies WebSockets
to Traefik; the origin firewall remains source-restricted. No persistent storage.

## Deploy

Update the source revision and hash in the module, then run from the repo root:

```sh
direnv exec . deploy .#chunkymonkey
```

Quadlet builds the upstream Dockerfile natively on ARM64. Restarting the relay
disconnects active sockets; clients must reconnect. Check `/health` and `/ready`,
then verify paired traffic both ways and reconnects after deployment.

## Clients

```text
PASEO_RELAY_ENABLED=true
PASEO_RELAY_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_PUBLIC_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_USE_TLS=true
PASEO_RELAY_PUBLIC_USE_TLS=true
```

- Endpoint changes require a new pairing offer.
- Upstream fallback: `relay.paseo.sh:443`.
