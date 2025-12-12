# Quick Reference: Dual Config Matrix Generator

## TL;DR

Use ArgoCD Matrix Generator to read **TWO** config.json files and merge their values.

## Key Concept

```
configs/config.json        +        live-configs/config.json
(App metadata)                      (Secrets, DB, Resources)
        ↓                                      ↓
    .app.* variables        +       .live.* variables
                            ↓
              Combined in ApplicationSet template
```

## File Structure

```
configs/overlays/dev/dev-app1/
  └── config.json                    # .app.* variables

live-configs/dev/dev-app1/
  └── config.json                    # .live.* variables
```

## Matrix Generator Setup

```yaml
generators:
  - matrix:
      generators:
        - git:
            files:
              - path: "configs/overlays/*/*/config.json"
            pathParamPrefix: app    # Creates .app.* variables

        - git:
            files:
              - path: "live-configs/*/*/config.json"
            pathParamPrefix: live   # Creates .live.* variables

      # Filter to match only correct pairs
      template:
        template:
          metadata:
            name: '{{if eq .app.matchKey .live.matchKey}}{{.app.instance}}{{end}}'
```

## Required matchKey Field

Both config.json files MUST have the same `matchKey`:

**configs/overlays/dev/dev-app1/config.json**:
```json
{
  "matchKey": "dev-app1",   ← Must match
  "appName": "nginx-app",
  ...
}
```

**live-configs/dev/dev-app1/config.json**:
```json
{
  "matchKey": "dev-app1",   ← Must match
  "dbConfig": {...},
  ...
}
```

## Accessing Values

### From configs/config.json → Use `.app.*`

```yaml
namespace: '{{.app.namespace}}'
replicas: {{.app.replicas}}
image: '{{.app.image.repository}}:{{.app.image.tag}}'
team: '{{.app.labels.team}}'
```

### From live-configs/config.json → Use `.live.*`

```yaml
dbHost: '{{.live.dbConfig.host}}'
cpu: '{{.live.resources.cpu}}'
memory: '{{.live.resources.memory}}'
vaultPath: '{{.live.secrets.vaultPath}}'
```

## Example Values

### configs/config.json
```json
{
  "matchKey": "dev-app1",
  "appName": "nginx-app",
  "replicas": 1,
  "namespace": "development",
  "image": {
    "repository": "nginx",
    "tag": "1.25-alpine"
  }
}
```

### live-configs/config.json
```json
{
  "matchKey": "dev-app1",
  "dbConfig": {
    "host": "dev-db.company.com",
    "database": "app1_dev"
  },
  "resources": {
    "cpu": "500m",
    "memory": "1Gi"
  }
}
```

### ApplicationSet Template Usage
```yaml
template:
  metadata:
    name: '{{.app.instance}}'              # from configs
    namespace: '{{.app.namespace}}'         # from configs
    annotations:
      db-host: '{{.live.dbConfig.host}}'   # from live-configs
      cpu: '{{.live.resources.cpu}}'       # from live-configs
```

## Validation

Run the validation script:
```bash
./validate-dual-config.sh
```

Expected output:
```
✓ All validations passed!
```

## Common Issues

### 1. No Applications Generated

**Problem**: matchKey values don't match

**Solution**:
```bash
# Check matchKeys align
jq '.matchKey' configs/overlays/dev/dev-app1/config.json
jq '.matchKey' live-configs/dev/dev-app1/config.json
```

### 2. Getting N×M Applications Instead of N

**Problem**: Missing template filter or matchKey

**Solution**: Ensure template has the filter:
```yaml
template:
  template:
    metadata:
      name: '{{if eq .app.matchKey .live.matchKey}}{{.app.instance}}{{end}}'
```

### 3. Variable Not Found

**Problem**: Using wrong prefix

**Solution**:
- Configs → `.app.*`
- Live-configs → `.live.*`

## Files Created

- `applicationset-dual-config.yaml` - Main ApplicationSet
- `DUAL-CONFIG-GUIDE.md` - Comprehensive guide
- `validate-dual-config.sh` - Validation script
- `configs/overlays/*/*/config.json` - App configs (updated)
- `live-configs/*/*/config.json` - Live configs (new)

## Usage

1. **Validate**: `./validate-dual-config.sh`
2. **Apply**: `kubectl apply -f applicationset-dual-config.yaml`
3. **Check**: ArgoCD UI → Applications

## Comparison

| Feature | Single Config | Dual Config |
|---------|--------------|-------------|
| Config files | 1 | 2 |
| Separation | ❌ | ✅ |
| Access control | Same | Different |
| Complexity | Low | Medium |
| Security | Basic | Enhanced |

## Next Steps

1. ✅ Understand the concept
2. ✅ Review file structure
3. ✅ Run validation script
4. ✅ Apply ApplicationSet
5. ✅ Verify in ArgoCD UI

For detailed information, see [DUAL-CONFIG-GUIDE.md](./DUAL-CONFIG-GUIDE.md)
