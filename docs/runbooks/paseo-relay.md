# Paseo Relay operations

Use the [infrastructure workflow](terraform.md) with `terraform/railway`.
Terraform owns the project, service, domain, replicas, and declared variables;
[`main.tf`](../../terraform/railway/main.tf) is their source of truth.

The service builds from [meatcar/paseo-relay](https://github.com/meatcar/paseo-relay).
That fork syncs upstream through `.github/workflows/sync-upstream.yml`, and
Railway autodeploys it. Updates can disconnect active sessions.

## Railway-owned settings

These settings are outside the provider's schema:

| Setting | Value |
| --- | --- |
| Healthcheck | `/ready`, 60-second timeout |
| Per-replica limits | 1 vCPU, 2 GB RAM |
| Serverless | Enabled |
| Restart policy | Always |

Sleeping reduces idle cost but adds cold-start latency. Clients must tolerate
reconnects after sleep, deploys, or network interruptions.

## Client configuration

```text
PASEO_RELAY_ENABLED=true
PASEO_RELAY_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_PUBLIC_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_USE_TLS=true
PASEO_RELAY_PUBLIC_USE_TLS=true
```

Generate a new pairing offer after changing the endpoint; offers contain it.
The upstream fallback is `relay.paseo.sh:443`.

## After a deployment

Check `/health` and `/ready` on `https://paseo.denys.me`, then pair a client and
verify bidirectional traffic and reconnects. Use Railway logs and metrics to
investigate failures. The relay is stateless.
