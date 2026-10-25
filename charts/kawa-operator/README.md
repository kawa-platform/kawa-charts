# kawa-operator

Installs the **kawa operator**, which manages a kawa gateway through `VirtualTopic` resources. The user
documentation is `docs/operator.md` in kawa-docs.

```bash
helm install kawa-operator ./charts/kawa-operator -n kawa -f operator-values.yaml
```

## Values

| Value | Meaning |
|-------|---------|
| `gateway.adminUrl` | The gateway's admin API (required). |
| `gateway.auth.existingSecret` | Secret, key `client-secret`, with the operator client's secret (required). Mounted as a file. |
| `gateway.tls.caSecret` | Secret, key `ca.crt`, for an https admin API with a private CA. |
| `namespaceSelector` | Label selector of the namespaces to serve. Empty serves all. |
| `resyncInterval` | How often synced topics are compared with the gateway again (default `5m`). |
| `metrics.enabled` | Serve controller-runtime metrics over HTTPS on `:8443` (default `false`). |

The operator's client id on the gateway is always `kawa-operator`.

## What the chart adds

- The `VirtualTopic` CRD, copied from kawa-operator `config/crd/bases` (regenerate it there with `make manifests`).
  It carries `helm.sh/resource-policy: keep`, so uninstalling the chart leaves the CRD and every `VirtualTopic`.
- Aggregated ClusterRoles that give the built-in `view`, `edit` and `admin` roles access to `VirtualTopic`.
- RBAC for the operator itself, and leader election. The lease is named after the release, so several releases
  can share a namespace.
- With `metrics.enabled`: the Service `<release>-metrics`, the RBAC the endpoint needs to check scrapers' tokens,
  and the ClusterRole `<release>-metrics-reader` to bind to a scraper's ServiceAccount.
