# Quick Reference: Dual Config Matrix Generator

## TL;DR

Use ArgoCD Matrix Generator with **dependent path pattern** to combine values from **TWO** config.json files without field collisions.

## Key Concept

```
Generator 1: configs/config.json          Generator 2: live-configs/config.json
(contains configLiveDir field)     →     (path uses {{.configLiveDir}})
                ↓                                      ↓
      Automatic 1:1 matching - NO Cartesian product!
```

## The Pattern

```yaml
generators:
  - matrix:
      generators:
        # Step 1: Read app configs
        - git:
            files:
              - path: "configs/overlays/*/*/config.json"
            pathParamPrefix: app

        # Step 2: Read ONLY matching live config
        - git:
            files:
              - path: "live-configs/{{.configLiveDir}}/config.json"  # ← Dependent!
            pathParamPrefix: live
```

## File Structure

```
configs/overlays/dev/dev-app1/
  └── config.json                    # Contains configLiveDir: "dev/dev-app1"

live-configs/dev/dev-app1/          # ← Path matches configLiveDir value
  └── config.json                    # Loaded automatically!
```

## Required Field: configLiveDir

**configs/overlays/dev/dev-app1/config.json**:
```json
{
  "instance": "dev-app1",
  "namespace": "development",
  "configLiveDir": "dev/dev-app1",  ← MUST point to live config directory
  "replicas": 1
}
```

**live-configs/dev/dev-app1/config.json**:
```json
{
  "dbConfig": {
    "host": "dev-db.company.com"
  },
  "resources": {
    "cpu": "500m"
  }
}
```

## Accessing Values in Templates

### JSON Fields (No Prefix Needed)

Both config files' JSON fields are accessible directly:

```yaml
# From configs/config.json
name: '{{.instance}}'
namespace: '{{.namespace}}'
replicas: {{.replicas}}
team: '{{.labels.team}}'
image: '{{.image.repository}}:{{.image.tag}}'

# From live-configs/config.json
dbHost: '{{.dbConfig.host}}'
cpu: '{{.resources.cpu}}'
memory: '{{.resources.memory}}'
vaultPath: '{{.secrets.vaultPath}}'
```

### Path Fields (Use Prefix)

Path-related fields REQUIRE the prefix:

```yaml
# From configs path (use .app prefix)
configPath: '{{.app.path.path}}'          # configs/overlays/dev/dev-app1
configDir: '{{.app.path.basename}}'       # dev-app1

# From live-configs path (use .live prefix)
livePath: '{{.live.path.path}}'           # live-configs/dev/dev-app1
liveDir: '{{.live.path.basename}}'        # dev-app1
```

## ⚠️ Critical: pathParamPrefix Only Affects Paths!

```yaml
pathParamPrefix: app  # Creates: .app.path, .app.path.basename
                      # Does NOT create: .app.instance, .app.namespace
```

**What gets prefixed:**
- ✅ `.app.path.path`
- ✅ `.app.path.basename`
- ✅ `.app.path.segments`
- ✅ `.app.path.filename`

**What does NOT get prefixed:**
- ❌ `.instance` (stays as `.instance`)
- ❌ `.namespace` (stays as `.namespace`)
- ❌ `.dbConfig` (stays as `.dbConfig`)

This is why we use **dependent paths**, not field prefixing!

## How It Avoids Cartesian Product

### ❌ Without Dependent Path
```yaml
- git:
    files: ["configs/*/*/config.json"]
- git:
    files: ["live-configs/*/*/config.json"]
```
**Result:** 2 × 2 = **4 apps** (unwanted combinations)

### ✅ With Dependent Path
```yaml
- git:
    files: ["configs/*/*/config.json"]
- git:
    files: ["live-configs/{{.configLiveDir}}/config.json"]
```
**Result:** **2 apps** (only matching pairs)

## Complete Example

### ApplicationSet
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: dual-config-apps
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://github.com/company/configs.git
              files:
                - path: "apps/*/*/config.json"
              pathParamPrefix: app
          - git:
              repoURL: https://github.com/company/configs-live.git
              files:
                - path: "{{.configLiveDir}}/config.json"
              pathParamPrefix: live
  template:
    metadata:
      name: '{{.instance}}'
    spec:
      sources:
        - repoURL: https://github.com/company/configs.git
          path: '{{.app.path.path}}'
        - repoURL: https://github.com/company/configs-live.git
          path: 'live/{{.configLiveDir}}'
      destination:
        namespace: '{{.namespace}}'
        server: https://kubernetes.default.svc
```

## Validation

```bash
# Check configLiveDir matches directory
jq '.configLiveDir' configs/overlays/dev/dev-app1/config.json
# Output: "dev/dev-app1"

# Verify live config exists at that path
ls live-configs/dev/dev-app1/config.json
# Should exist!

# Run validation script
./validate-dual-config.sh
```

## Common Issues

### 1. No Applications Generated

**Problem:** `configLiveDir` doesn't match actual directory

**Solution:**
```bash
# Check value in config
jq '.configLiveDir' configs/overlays/dev/dev-app1/config.json

# Verify file exists
ls live-configs/dev/dev-app1/config.json
```

### 2. Field Not Found Error

**Problem:** Trying to use prefix on JSON fields

**Wrong:**
```yaml
name: '{{.app.instance}}'  # ❌ .app prefix doesn't work for JSON fields
```

**Right:**
```yaml
name: '{{.instance}}'      # ✅ JSON fields have no prefix
path: '{{.app.path.path}}' # ✅ Path fields need prefix
```

### 3. Cartesian Product (Too Many Apps)

**Problem:** Not using dependent path in second generator

**Wrong:**
```yaml
- git:
    files: ["live-configs/*/*/config.json"]  # ❌ Creates all combinations
```

**Right:**
```yaml
- git:
    files: ["live-configs/{{.configLiveDir}}/config.json"]  # ✅ Only matching
```

## Use Cases

| Scenario | configs/config.json | live-configs/config.json |
|----------|---------------------|--------------------------|
| **Development** | Image tags, replicas, namespace | Dev DB, low resources |
| **Staging** | Image tags, replicas, namespace | Stage DB, medium resources |
| **Production** | Image tags, replicas, namespace | Prod DB, high resources |

Each environment has:
- Same app config structure
- Different live config values
- Automatic 1:1 pairing via `configLiveDir`

## Key Benefits

1. ✅ **No Field Collisions** - Dependent path prevents conflicts
2. ✅ **Simple Access** - No prefixes needed for JSON fields
3. ✅ **1:1 Matching** - No Cartesian product
4. ✅ **Separate Repos** - Different access controls
5. ✅ **Independent Updates** - Change one without touching the other

## Next Steps

1. ✅ Understand the dependent path pattern
2. ✅ Create config.json with `configLiveDir` field
3. ✅ Create matching live-configs directory
4. ✅ Apply ApplicationSet
5. ✅ Verify in ArgoCD UI

For detailed information, see [DUAL-CONFIG-GUIDE.md](./DUAL-CONFIG-GUIDE.md)

## Reference

Based on: [ArgoCD Matrix Generator - Two Git Generators](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Matrix/#example-two-git-generators-using-pathparamprefix)
