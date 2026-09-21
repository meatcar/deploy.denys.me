# Paseo Relay

- [Infrastructure workflow](../../terraform/README.md)
- [Service and variables](../../terraform/railway/main.tf)
- [DNS records](../../terraform/dns.tf)
- [Source fork](https://github.com/meatcar/paseo-relay): upstream sync, Railway autodeploy

## Railway-owned settings

These settings are outside the provider's schema:

| Setting | Value |
| --- | --- |
| Healthcheck | `/ready`, 60-second timeout |
| Per-replica limits | 1 vCPU, 2 GB RAM |
| Serverless | Enabled |
| Restart policy | Always |

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
- Clients must tolerate cold starts and reconnects.
- After deploy: check `/health` and `/ready`, pair a client, test traffic both ways and reconnects.
