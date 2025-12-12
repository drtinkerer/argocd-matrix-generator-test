# ArgoCD Dual Config Matrix Generator Example

This repository demonstrates how to use **ArgoCD ApplicationSet with Matrix Generator** to combine values from **two separate config.json files** - one for application configuration and another for live/sensitive configuration.

## 🎯 What This Solves

When managing applications with ArgoCD, you often need to:
- Separate application configs from sensitive/live configs
- Use different Git repositories or access controls for different config types
- Merge values from multiple sources in your ApplicationSet

This example shows you how to achieve this using ArgoCD's Matrix Generator.

## 📁 Repository Structure

```
.
├── applicationset-dual-config.yaml    # ArgoCD ApplicationSet with Matrix Generator
│
├── configs/                            # Application configurations
│   ├── base/                          # Base Kubernetes resources
│   │   ├── deployment.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   └── overlays/                      # Environment-specific overlays
│       ├── dev/
│       │   ├── dev-app1/
│       │   │   ├── config.json        # App metadata, image, replicas
│       │   │   └── kustomization.yaml
│       │   └── dev-app2/
│       │       ├── config.json
│       │       └── kustomization.yaml
│       └── stage/
│           └── stage-app1/
│               ├── config.json
│               └── kustomization.yaml
│
├── live-configs/                       # Live/sensitive configurations
│   ├── dev/
│   │   ├── dev-app1/
│   │   │   ├── config.json            # DB config, secrets, resources
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
├── DUAL-CONFIG-GUIDE.md                # Comprehensive documentation
├── QUICK-REFERENCE.md                  # Quick reference guide
└── validate-dual-config.sh             # Validation script
```

## 🚀 Quick Start

### 1. Validate the Configuration

Run the validation script to ensure everything is set up correctly:

```bash
./validate-dual-config.sh
```

Expected output:
```
✓ All validations passed!
Your dual config.json setup is ready to use.
```

### 2. Apply the ApplicationSet

Deploy to your ArgoCD instance:

```bash
kubectl apply -f applicationset-dual-config.yaml
```

### 3. Verify in ArgoCD

Check the ArgoCD UI to see the generated applications:
- `dev-app1`
- `dev-app2`
- `stage-app1`

## 💡 How It Works

### Dual Config.json Approach

The matrix generator reads **two config.json files** for each application:

**1. configs/overlays/dev/dev-app1/config.json** (Application Config):
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

**2. live-configs/dev/dev-app1/config.json** (Live/Sensitive Config):
```json
{
  "matchKey": "dev-app1",
  "dbConfig": {
    "host": "dev-db.internal.company.com",
    "database": "app1_dev"
  },
  "resources": {
    "cpu": "500m",
    "memory": "1Gi"
  }
}
```

### Matrix Generator Configuration

```yaml
generators:
  - matrix:
      generators:
        # Generator 1: Read app configs → .app.* variables
        - git:
            files:
              - path: "configs/overlays/*/*/config.json"
            pathParamPrefix: app

        # Generator 2: Read live configs → .live.* variables
        - git:
            files:
              - path: "live-configs/*/*/config.json"
            pathParamPrefix: live

      # Filter: Only match when matchKeys align
      template:
        template:
          metadata:
            name: '{{if eq .app.matchKey .live.matchKey}}{{.app.instance}}{{end}}'
```

### Accessing Values in Templates

**From configs** (prefix `.app.*`):
```yaml
namespace: '{{.app.namespace}}'
replicas: {{.app.replicas}}
image: '{{.app.image.repository}}:{{.app.image.tag}}'
```

**From live-configs** (prefix `.live.*`):
```yaml
dbHost: '{{.live.dbConfig.host}}'
cpu: '{{.live.resources.cpu}}'
memory: '{{.live.resources.memory}}'
```

## 📚 Documentation

- **[QUICK-REFERENCE.md](./QUICK-REFERENCE.md)** - Quick reference for common tasks
- **[DUAL-CONFIG-GUIDE.md](./DUAL-CONFIG-GUIDE.md)** - Comprehensive guide with examples and troubleshooting

## ✨ Key Features

1. **Separation of Concerns**: Application config separate from sensitive data
2. **Flexible Access Control**: Different repos can have different permissions
3. **Matched Pairs**: Uses `matchKey` to prevent Cartesian product explosion
4. **Dual Variables**: Access values with `.app.*` and `.live.*` prefixes
5. **Multi-Source**: Each application combines both config sources
6. **Validated**: Includes comprehensive validation script

## 🔑 Key Requirement: matchKey

Both config.json files **must have matching `matchKey` values**:

```json
// configs/config.json
{
  "matchKey": "dev-app1",  ← Must match
  ...
}

// live-configs/config.json
{
  "matchKey": "dev-app1",  ← Must match
  ...
}
```

This ensures the matrix generator creates **only matching pairs** instead of a full Cartesian product.

## 🛠️ Common Use Cases

### Separate Repositories

In production, you might use different repositories:

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: https://github.com/company/app-configs.git
            files:
              - path: "overlays/*/*/config.json"
            pathParamPrefix: app
        - git:
            repoURL: https://github.com/company/app-configs-live.git  # Restricted repo
            files:
              - path: "*/*/config.json"
            pathParamPrefix: live
```

### Different Access Controls

- **app-configs**: Accessible to dev team
- **app-configs-live**: Restricted to ops/security team

### Independent Update Cycles

- Update app configs (image tags, replicas) independently
- Update live configs (DB hosts, resource limits) independently
- ArgoCD automatically syncs changes from both

## 🐛 Troubleshooting

### No Applications Generated

Check that matchKeys align:
```bash
./validate-dual-config.sh
```

### Wrong Number of Applications

Ensure template filter exists:
```yaml
template:
  template:
    metadata:
      name: '{{if eq .app.matchKey .live.matchKey}}{{.app.instance}}{{end}}'
```

### Cannot Access Variables

- Use `.app.*` for configs values
- Use `.live.*` for live-configs values
- Check field exists in config.json: `jq . configs/overlays/dev/dev-app1/config.json`

## 📖 Additional Resources

- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Matrix Generator Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/)
- [Git Generator Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)

## 🤝 Contributing

This is an example repository. Feel free to fork and adapt for your use case!

## 📝 License

MIT License - Feel free to use this example in your projects.

---

**Quick Links:**
- [Quick Reference](./QUICK-REFERENCE.md) - Fast lookup
- [Complete Guide](./DUAL-CONFIG-GUIDE.md) - Detailed documentation
- [Validation Script](./validate-dual-config.sh) - Test your setup
