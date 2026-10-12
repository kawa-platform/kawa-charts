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
- **Studio**: `KAWA_API_UPSTREAM` points the image's nginx `/api/` at the gateway's admin Service (prefix stripped).

## Choosing a config source

- `gateway.config`: the chart renders the file from values.
- `gateway.existingConfigMap`: use a ConfigMap you manage, with a `config.yaml` key. The chart cannot read that
  file, so set `gateway.service.kafkaPort` and `adminPort` to match it.

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

`gateway.image` / `studio.image` default to the local builds `kawa-gateway:latest` and `kawa-studio:latest`
(`docker build -t kawa-gateway .` in each repo). Point them at your registry for a real cluster.

See [values.yaml](values.yaml) for every option.
