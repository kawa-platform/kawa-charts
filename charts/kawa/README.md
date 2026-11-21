# kawa

Installs **kawa-gateway** and **kawa-studio** together.

```bash
helm install kawa ./charts/kawa -f my-values.yaml
```

`gateway.config` in `my-values.yaml` is the gateway's `config.yaml`, unchanged. The chart mounts it at `/etc/kawa/config.yaml`
through a ConfigMap, so the gateway docs apply as written. Pods restart when it changes.

## What the chart adds

- **Secrets**: `KAWA_ADMIN_PASSWORD` and `KAWA_SIGNING_KEY` come from a Secret, generated on first install and
  kept across upgrades. Use them in the config as `${KAWA_ADMIN_PASSWORD}` and `${KAWA_SIGNING_KEY}`. Bring your
  own with `gateway.secrets.existingSecret` (keys `admin-password` and `signing-key`). Other secrets go in
  `gateway.extraEnv` and are referenced from the config the same way.
- **advertised.host**: when the config leaves it out, the gateway advertises its Service's cluster DNS name.
- **Ports**: the Service and container ports follow the config, from `listeners[0].port` and `admin.port`
  (defaults 9092 and 8080). Only the first listener is exposed by the Service.
- **Probes**: with `admin.enabled: true`, the readiness probe calls `GET /health/ready` on the admin port, so a
  pod whose view of the Kafka cluster is stale leaves the Service until it recovers. Otherwise it is a TCP check
  on the Kafka port. Liveness is always a TCP check on the Kafka port.
- **Studio**: `KAWA_API_UPSTREAM` points the image's nginx `/api/` at the gateway's admin Service (prefix stripped).

## Keeping the config in its own file

`gateway.config` is the only config source: the chart reads it to set ports and probes. To keep the gateway config
apart from the rest of your values, nest it under `gateway.config` in a file of its own and pass both:

```bash
helm install kawa ./charts/kawa -f my-values.yaml -f gateway-config.yaml
```

`gateway.existingConfigMap` and `gateway.service.kafkaPort`/`adminPort` were removed in 0.2.0; the install fails
if they are still set.

## Reaching the admin API from Studio

Studio's API base is fixed at build time (`VITE_API_BASE`, `VITE_ADMIN_API_BASE`, default `http://localhost:8080`).
Pick the setup that matches your image:

| Studio image built with                       | Setup                                                                                        |
|-----------------------------------------------|----------------------------------------------------------------------------------------------|
| defaults (local use)                          | No ingress. Port-forward Studio to `5173` and the gateway to `8080` (see the install notes). |
| `VITE_API_BASE=/api VITE_ADMIN_API_BASE=/api` | `ingress.enabled=true`; Studio's nginx forwards `/api` to the gateway, same origin.          |
| `https://kawa-api.example.com`                | `ingress.enabled=true` plus `gateway.adminIngress.enabled=true` with that host.              |

The config's `admin.auth.settings.loginUrl`, `redirectUris` and `admin.cors.allowedOrigins` must use the URL
browsers open Studio on: `ingress.host` when the ingress is enabled, `http://localhost:5173` otherwise.

## Kafka clients

Clients connect to the gateway Service on the listener port. The gateway advertises `advertised.host:port`
(default: the Service's cluster DNS name), so for clients outside the cluster set `gateway.service.type`
(e.g. `LoadBalancer`) and `advertised.host` in the config to the address they use.

## Images

`gateway.image` / `studio.image` default to `ghcr.io/kawa-platform/kawa-gateway` and `kawa-studio`, tagged with the
versions pinned in `values.yaml`, so a chart version pins its images. If the packages are private, set `imagePullSecrets`.

To use local builds (`docker build -t kawa-gateway .` in each repo), override them:

```
--set gateway.image.repository=kawa-gateway,gateway.image.tag=latest \
--set studio.image.repository=kawa-studio,studio.image.tag=latest
```

See [values.yaml](values.yaml) for every option.
