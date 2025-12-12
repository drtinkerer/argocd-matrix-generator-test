# ArgoCD Dual Config Matrix Generator Example

This repository demonstrates how to use **ArgoCD ApplicationSet with Matrix Generator** to combine values from **two separate config.json files** using the **dependent path pattern**.

## 🎯 The Problem This Solves

When managing applications with ArgoCD, you often need to:
- Separate application configs from sensitive/live configs
- Use different Git repositories (or directories) with different access controls
- Merge values from multiple config.json files without manual coordination

**The Challenge:** ArgoCD's `pathParamPrefix` only prefixes PATH variables, NOT JSON fields from config.json. This means fields from the second config.json would overwrite the first, creating conflicts.

**The Solution:** Use a **dependent path pattern** where the second generator's file path references a field from the first generator, creating automatic 1:1 matching instead of a Cartesian product.

## 🔑 Key Pattern: Dependent Path

```yaml
generators:
  - matrix:
      generators:
        # Generator 1: Scans all app configs
        - git:
            files:
              - path: "configs/overlays/*/*/config.json"
            pathParamPrefix: app

        # Generator 2: Loads ONLY the matching live config
        # Uses {{.configLiveDir}} from Generator 1
        - git:
            files:
              - path: "live-configs/{{.configLiveDir}}/config.json"  # ← Dependent path!
            pathParamPrefix: live
```

**How it works:**
- Generator 1 reads `configs/overlays/dev/dev-app1/config.json` which contains `"configLiveDir": "dev/dev-app1"`
- Generator 2 uses that value to load `live-configs/dev/dev-app1/config.json`
- **Result:** Only matching pairs are created (dev-app1 ↔ dev-app1), NOT a Cartesian product!

## 📁 Repository Structure

```
.
├── applicationset-dual-config.yaml    # ArgoCD ApplicationSet
│
├── configs/                            # Application configurations
│   └── overlays/
│       └── dev/
│           ├── dev-app1/
│           │   ├── config.json        # Contains: instance, namespace, configLiveDir, etc.
│           │   └── kustomization.yaml
│           └── dev-app2/
│               ├── config.json
│               └── kustomization.yaml
│
└── live-configs/                       # Live/sensitive configurations
    └── dev/
        ├── dev-app1/
        │   ├── config.json            # Contains: dbConfig, secrets, resources
        │   ├── kustomization.yaml
        │   └── config/
        │       └── app.properties
        └── dev-app2/
            ├── config.json
            ├── kustomization.yaml
            └── config/
                └── app.properties
```

## 💡 The Two Config Files

### configs/overlays/dev/dev-app1/config.json
```json
{
  "appName": "nginx-app",
  "environment": "dev",
  "instance": "dev-app1",
  "replicas": 1,
  "namespace": "development",
  "configLiveDir": "dev/dev-app1",  ← Links to live config!
  "labels": {
    "team": "platform",
    "tier": "frontend"
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
  "dbConfig": {
    "host": "dev-db.internal.company.com",
    "port": 5432,
    "database": "app1_dev"
  },
  "secrets": {
    "vaultPath": "secret/dev/app1"
  },
  "resources": {
    "cpu": "500m",
    "memory": "1Gi"
  }
}
```

## 🚀 Quick Start

### 1. Validate Configuration

```bash
./validate-dual-config.sh
```

### 2. Update Destination Server

Edit `applicationset-dual-config.yaml` and set your cluster:

```yaml
destination:
  namespace: '{{.namespace}}'
  server: https://your-kubernetes-cluster
```

### 3. Apply ApplicationSet

```bash
kubectl apply -f applicationset-dual-config.yaml
```

### 4. Verify Applications

```bash
kubectl get applications -n argocd | grep dev-app
```

You should see:
- `dev-app1` - Created from dev-app1 configs + dev-app1 live configs
- `dev-app2` - Created from dev-app2 configs + dev-app2 live configs

## 🔍 How to Access Fields in Templates

### From configs/config.json (Generator 1)

Access JSON fields directly (no prefix):
```yaml
instance: '{{.instance}}'
namespace: '{{.namespace}}'
replicas: '{{.replicas}}'
team: '{{.labels.team}}'
image: '{{.image.repository}}:{{.image.tag}}'
```

Access path fields with prefix:
```yaml
path: '{{.app.path.path}}'          # configs/overlays/dev/dev-app1
basename: '{{.app.path.basename}}'  # dev-app1
```

### From live-configs/config.json (Generator 2)

Access JSON fields directly (no prefix):
```yaml
dbHost: '{{.dbConfig.host}}'
dbPort: '{{.dbConfig.port}}'
cpu: '{{.resources.cpu}}'
memory: '{{.resources.memory}}'
vaultPath: '{{.secrets.vaultPath}}'
```

Access path fields with prefix:
```yaml
path: '{{.live.path.path}}'          # live-configs/dev/dev-app1
basename: '{{.live.path.basename}}'  # dev-app1
```

## ⚠️ Important: Why pathParamPrefix Alone Doesn't Work

**Common Misconception:** "Using `pathParamPrefix: app` and `pathParamPrefix: live` will namespace all fields."

**Reality:** `pathParamPrefix` ONLY prefixes path-related variables:
- ✅ `.app.path`, `.app.path.basename`, `.app.path.segments`
- ❌ NOT `.instance`, `.namespace`, `.replicas` (these remain unprefixed)

This is why we use the **dependent path pattern** instead of trying to namespace JSON fields.

## 📊 Comparison: With vs Without Dependent Path

### ❌ Without Dependent Path (Cartesian Product)
```yaml
- git:
    files:
      - path: "configs/*/*/config.json"
- git:
    files:
      - path: "live-configs/*/*/config.json"
```
**Result:** 2 configs × 2 live-configs = **4 applications** (many unwanted)

### ✅ With Dependent Path (1:1 Matching)
```yaml
- git:
    files:
      - path: "configs/*/*/config.json"
- git:
    files:
      - path: "live-configs/{{.configLiveDir}}/config.json"
```
**Result:** **2 applications** (only matching pairs)

## 🛠️ Use Cases

### 1. Separate Repositories

In production, use different Git repositories for security:

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: https://github.com/company/app-configs.git
            files:
              - path: "apps/*/*/config.json"
            pathParamPrefix: app
        - git:
            repoURL: https://github.com/company/app-configs-live.git  # Restricted access
            files:
              - path: "{{.configLiveDir}}/config.json"
            pathParamPrefix: live
```

### 2. Different Access Controls

- **app-configs**: Accessible to development team (image tags, replicas, namespaces)
- **app-configs-live**: Restricted to ops/security team (DB credentials, vault paths, resource limits)

### 3. Independent Update Cycles

- Update app configs (image versions) without touching sensitive configs
- Update live configs (resource limits, DB endpoints) without touching app definitions
- ArgoCD automatically syncs changes from both sources

## 🐛 Troubleshooting

### No Applications Generated

Check that `configLiveDir` values are correct:
```bash
jq '.configLiveDir' configs/overlays/dev/dev-app1/config.json
# Should output: "dev/dev-app1"

# Verify matching file exists:
ls -la live-configs/dev/dev-app1/config.json
```

### Shared Resource Warning

If you see warnings about shared ConfigMaps/resources, ensure each app has unique resource names in their kustomization.yaml files.

### Template Errors

Run validation:
```bash
./validate-dual-config.sh
```

Check ApplicationSet status:
```bash
kubectl describe applicationset dual-config-matrix-apps -n argocd
```

## 📚 Documentation

- **[QUICK-REFERENCE.md](./QUICK-REFERENCE.md)** - Quick lookup guide
- **[DUAL-CONFIG-GUIDE.md](./DUAL-CONFIG-GUIDE.md)** - Comprehensive guide with examples

## 📖 References

This pattern is based on the official ArgoCD documentation:
- [Matrix Generator - Two Git Generators Using pathParamPrefix](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Matrix/#example-two-git-generators-using-pathparamprefix)
- [Git Generator Documentation](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Git/)

## ✨ Key Takeaways

1. **Dependent Path Pattern**: Second generator references fields from first generator
2. **pathParamPrefix**: Only prefixes PATH variables, not JSON fields
3. **1:1 Matching**: Avoids Cartesian product by loading only matching configs
4. **Nested JSON Access**: Access nested fields directly (e.g., `{{.dbConfig.host}}`)
5. **Simple & Clean**: No need for unique field name prefixes or complex filtering

## 🤝 Contributing

This is an example repository demonstrating ArgoCD patterns. Feel free to fork and adapt!

## 📝 License

MIT License - Use freely in your projects.

---

**Quick Links:**
- [Quick Reference](./QUICK-REFERENCE.md)
- [Complete Guide](./DUAL-CONFIG-GUIDE.md)
- [Validation Script](./validate-dual-config.sh)
