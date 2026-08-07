# Paseo Relay on Railway

The Railway service builds from [`meatcar/paseo-relay`](https://github.com/meatcar/paseo-relay), a fork of [`getpaseo/paseo-relay`](https://github.com/getpaseo/paseo-relay). The fork syncs upstream `main` daily at 08:17 UTC and Railway autodeploys changes using the upstream Dockerfile.

## Service configuration

- Project: `paseo-relay`
- Environment: `production`
- Service source: `meatcar/paseo-relay`
- Branch: `main`
- Upstream sync: `.github/workflows/sync-upstream.yml` in the fork
- Public domain: `paseo.denys.me`
- Target port: `4000`
- Healthcheck: `/ready`
- Healthcheck timeout: `60s`
- Replicas: `1`
- Per-replica limit: `1 vCPU`, `2 GB RAM`
- Serverless: enabled to sleep during idle periods
- Restart policy: always

Apply the non-secret variables in [`variables.env`](./variables.env). `PORT` must match `PASEO_RELAY_PORT` so Railway's proxy and deployment healthcheck use the relay listener.

```sh
nix develop
railway login
railway init --name paseo-relay
railway add --repo meatcar/paseo-relay
railway variable set \
  PORT=4000 \
  ELIXIR_ERL_OPTIONS=+fnu \
  PASEO_RELAY_HOST=0.0.0.0 \
  PASEO_RELAY_PORT=4000 \
  PASEO_RELAY_MIN_CLUSTER_SIZE=1 \
  PASEO_RELAY_ACCEPTORS=10 \
  PASEO_RELAY_CONNECTIONS_PER_ACCEPTOR=100 \
  PASEO_RELAY_MEMORY_WATERMARK_BYTES=1610612736
railway domain paseo.denys.me --port 4000
```

Set the healthcheck, restart policy, replica count, per-replica CPU/memory limits, and serverless setting in the Railway service settings, then deploy the staged changes. The Railway CNAME and ownership-verification TXT records are managed in `terraform/dns.tf`.

## Paseo daemon configuration

```text
PASEO_RELAY_ENABLED=true
PASEO_RELAY_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_PUBLIC_ENDPOINT=paseo.denys.me:443
PASEO_RELAY_USE_TLS=true
PASEO_RELAY_PUBLIC_USE_TLS=true
```

Generate a new pairing offer after changing the daemon configuration because the offer carries the relay endpoint.

## Verification

```sh
curl --fail https://paseo.denys.me/health
curl --fail https://paseo.denys.me/ready
railway logs
railway metrics --memory --cpu --network --http
```

Then pair one client and verify traffic in both directions, daemon reconnect, and client reconnect.

## Operations

Upstream warns that relay restarts are user-visible. Autodeploy is intentionally enabled, so the daily fork sync can deploy an upstream commit and disconnect active sessions. Railway WebSockets have no inactivity timeout, but deploys and network interruptions still close existing connections.

Serverless sleeping is enabled to reduce idle cost. Railway may sleep the relay after an idle period, so the first connection afterward can experience a cold start or need to reconnect. Active outbound traffic keeps the service awake.

The relay is stateless. Roll back by selecting a previous Railway deployment, or point Paseo daemons back to `relay.paseo.sh:443` and generate new pairing offers.
