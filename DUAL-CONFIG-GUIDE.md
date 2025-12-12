# Dual Config.json Matrix Generator Guide

## Overview

This example demonstrates how to use ArgoCD's **Matrix Generator** with **two Git file generators** to read and merge values from **two separate config.json files**:

1. **configs/overlays/\*/\*/config.json** - Application metadata, image info, replicas, labels
2. **live-configs/\*/\*/config.json** - Environment-specific secrets, database config, resources

## Why Use Two Config Files?

### Separation of Concerns

- **configs/config.json**:
  - Application-level configuration
  - Image repository and tags
  - Replica counts
  - Team/component labels
  - Can be in a public or less-restricted repo

- **live-configs/config.json**:
  - Environment-specific sensitive data
  - Database connection strings
  - Resource limits (CPU/memory)
  - Secret vault paths
  - Typically in a restricted/private repo

### Benefits

1. **Security**: Sensitive configurations separated from application configs
2. **Access Control**: Different teams can manage different config files
3. **Flexibility**: Change environment configs without touching app configs
4. **Audit Trail**: Separate git histories for different concerns

## How It Works

### Matrix Generator Configuration

```yaml
generators:
  - matrix:
      generators:
        # Generator 1: Read configs/config.json
        - git:
            files:
              - path: "configs/overlays/*/*/config.json"
            pathParamPrefix: app

        # Generator 2: Read live-configs/config.json
        - git:
            files:
              - path: "live-configs/*/*/config.json"
            pathParamPrefix: live

      # Template filter to match only correct pairs
      template:
        metadata: {}
        spec: {}
        template:
          metadata:
            name: '{{if eq .app.matchKey .live.matchKey}}{{.app.instance}}{{end}}'
```

### How Matching Works

Without filtering, a matrix generator creates a **Cartesian product**:
- 3 apps in configs × 3 apps in live-configs = **9 combinations** ❌

With the `matchKey` filter, we get **only matching pairs**:
- dev-app1 (configs) + dev-app1 (live-configs) = 1 combination ✅
- dev-app2 (configs) + dev-app2 (live-configs) = 1 combination ✅
- stage-app1 (configs) + stage-app1 (live-configs) = 1 combination ✅
- **Total: 3 combinations** ✅

### The matchKey Field

Both config.json files must have a matching `matchKey`:

**configs/overlays/dev/dev-app1/config.json**:
```json
{
  "matchKey": "dev-app1",
  "appName": "nginx-app",
  "instance": "dev-app1",
  ...
}
```

**live-configs/dev/dev-app1/config.json**:
```json
{
  "matchKey": "dev-app1",
  "dbConfig": { ... },
  "resources": { ... },
  ...
}
```

The template filter `{{if eq .app.matchKey .live.matchKey}}` ensures only matching pairs are generated.

## Accessing Values in Templates

### From configs/config.json (prefix: `app.*`)

```yaml
replicas: '{{.app.replicas}}'
namespace: '{{.app.namespace}}'
image: '{{.app.image.repository}}:{{.app.image.tag}}'
team: '{{.app.labels.team}}'
```

### From live-configs/config.json (prefix: `live.*`)

```yaml
dbHost: '{{.live.dbConfig.host}}'
dbName: '{{.live.dbConfig.database}}'
cpu: '{{.live.resources.cpu}}'
memory: '{{.live.resources.memory}}'
vaultPath: '{{.live.secrets.vaultPath}}'
```

## Directory Structure

```
.
├── configs/                                    # App configurations
│   └── overlays/
│       ├── dev/
│       │   ├── dev-app1/
│       │   │   ├── config.json                # App metadata
│       │   │   └── kustomization.yaml
│       │   └── dev-app2/
│       │       ├── config.json
│       │       └── kustomization.yaml
│       └── stage/
│           └── stage-app1/
│               ├── config.json
│               └── kustomization.yaml
│
├── live-configs/                               # Live/sensitive configs
│   ├── dev/
│   │   ├── dev-app1/
│   │   │   ├── config.json                    # DB, secrets, resources
│   │   │   ├── kustomization.yaml
│   │   │   └── config/
│   │   │       └── app.properties
│   │   └── dev-app2/
│   │       ├── config.json
│   │       ├── kustomization.yaml
│   │       └── config/
│   │           └── app.properties
│   └── stage/
│       └── stage-app1/
│           ├── config.json
│           ├── kustomization.yaml
│           └── config/
│               └── app.properties
│
└── applicationset-dual-config.yaml             # Matrix ApplicationSet
```

## Complete Example

### configs/overlays/dev/dev-app1/config.json

```json
{
  "matchKey": "dev-app1",
  "appName": "nginx-app",
  "environment": "dev",
  "instance": "dev-app1",
  "replicas": 1,
  "namespace": "development",
  "configLiveDir": "dev/dev-app1",
  "labels": {
    "team": "platform",
    "tier": "frontend",
    "component": "web-server"
  },
  "image": {
    "repository": "nginx",
    "tag": "1.25-alpine"
  }
}
```

### live-configs/dev/dev-app1/config.json

```json
{
  "matchKey": "dev-app1",
  "dbConfig": {
    "host": "dev-db.internal.company.com",
    "port": 5432,
    "database": "app1_dev",
    "ssl": true
  },
  "secrets": {
    "vaultPath": "secret/dev/app1",
    "apiKeyName": "dev-api-key"
  },
  "resources": {
    "cpu": "500m",
    "memory": "1Gi"
  },
  "liveConfigVersion": "1.0.0"
}
```

### Generated ArgoCD Application

When the matrix generator processes these two files, it creates an ArgoCD Application with:

**Metadata**:
```yaml
name: dev-app1
labels:
  environment: dev                    # from configs
  team: platform                      # from configs
  app-name: nginx-app                 # from configs
  live-config-version: 1.0.0          # from live-configs
annotations:
  app.image.repository: nginx         # from configs
  app.image.tag: 1.25-alpine          # from configs
  live.db.host: dev-db.internal...    # from live-configs
  live.db.database: app1_dev          # from live-configs
  live.resources.cpu: 500m            # from live-configs
```

**Sources**:
```yaml
sources:
  - repoURL: https://github.com/...
    path: configs/overlays/dev/dev-app1      # from .app.path.path
  - repoURL: https://github.com/...
    path: live-configs/dev/dev-app1          # from .app.configLiveDir
```

## Using Values in Kustomize Patches

You can use these values in your kustomization patches:

### Example: Dynamic Deployment Patch

**configs/overlays/dev/dev-app1/patch-deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: {{.app.replicas}}
  template:
    metadata:
      labels:
        team: {{.app.labels.team}}
    spec:
      containers:
      - name: nginx
        image: {{.app.image.repository}}:{{.app.image.tag}}
        env:
        - name: DB_HOST
          value: "{{.live.dbConfig.host}}"
        - name: DB_PORT
          value: "{{.live.dbConfig.port}}"
        - name: DB_NAME
          value: "{{.live.dbConfig.database}}"
        - name: VAULT_PATH
          value: "{{.live.secrets.vaultPath}}"
        resources:
          requests:
            cpu: "{{.live.resources.cpu}}"
            memory: "{{.live.resources.memory}}"
```

## Testing Locally

1. **Verify config.json files exist in both locations**:
   ```bash
   find configs -name "config.json"
   find live-configs -name "config.json"
   ```

2. **Check that matchKeys align**:
   ```bash
   jq -r '.matchKey' configs/overlays/dev/dev-app1/config.json
   jq -r '.matchKey' live-configs/dev/dev-app1/config.json
   ```

3. **Validate JSON syntax**:
   ```bash
   jq . configs/overlays/dev/dev-app1/config.json
   jq . live-configs/dev/dev-app1/config.json
   ```

## Deployment

Apply the ApplicationSet to your ArgoCD cluster:

```bash
kubectl apply -f applicationset-dual-config.yaml
```

ArgoCD will:
1. Read all config.json files from both locations
2. Create matrix combinations
3. Filter to only matching pairs (using matchKey)
4. Generate ArgoCD Applications with merged values
5. Deploy each application with values from both config files

## Troubleshooting

### No Applications Generated

**Issue**: Matrix generator creates 0 applications

**Causes**:
1. `matchKey` values don't match between the two config.json files
2. Config.json files are missing in one of the locations
3. JSON syntax errors in config.json files

**Solution**:
```bash
# Check matchKeys match
diff <(jq -r '.matchKey' configs/overlays/dev/dev-app1/config.json) \
     <(jq -r '.matchKey' live-configs/dev/dev-app1/config.json)

# Validate JSON
jq . configs/overlays/dev/dev-app1/config.json
jq . live-configs/dev/dev-app1/config.json
```

### Wrong Number of Applications

**Issue**: Getting N×M applications instead of N

**Cause**: Template filter not working or matchKey missing

**Solution**: Ensure both config.json files have `matchKey` and the template filter is present:
```yaml
template:
  metadata:
    name: '{{if eq .app.matchKey .live.matchKey}}{{.app.instance}}{{end}}'
```

### Cannot Access Values

**Issue**: Template variable not found: `{{.live.dbConfig.host}}`

**Cause**: Using wrong prefix or field doesn't exist in config.json

**Solution**:
- Check prefix: `app.*` for configs, `live.*` for live-configs
- Verify field exists in the config.json file
- Check JSON structure with `jq`

## Comparison with Single Config Approach

| Aspect | Single Config | Dual Config (This Approach) |
|--------|--------------|----------------------------|
| **Security** | All configs in one file | Sensitive data separated |
| **Access Control** | Same for all configs | Different repos/permissions |
| **Maintenance** | Simple, one file | More complex, two files |
| **Flexibility** | Limited | High - independent updates |
| **Use Case** | Small apps, dev/test | Production, enterprise |

## Best Practices

1. **Consistent matchKey**: Use a predictable pattern (e.g., `{env}-{app}{instance}`)
2. **Schema Validation**: Use JSON schema to validate both config files
3. **Documentation**: Document what goes in each config.json
4. **Version Control**: Use separate repos for configs and live-configs
5. **Access Control**: Restrict live-configs repo to ops/security team
6. **Naming Convention**: Keep directory structures aligned between repos

## Advanced: Multi-Repo Setup

For production, use separate Git repositories:

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: https://gitlab.com/company/app-configs.git    # Public/less restricted
            files:
              - path: "overlays/*/*/config.json"
            pathParamPrefix: app
        - git:
            repoURL: https://gitlab.com/company/app-configs-live.git  # Private/restricted
            files:
              - path: "*/*/config.json"
            pathParamPrefix: live
```

This allows:
- Different access controls
- Independent update cycles
- Separate audit trails
- Better security posture
