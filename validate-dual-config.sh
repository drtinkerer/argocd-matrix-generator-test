#!/bin/bash

# Validation script for dual config.json setup
# This script validates that:
# 1. All config.json files have valid JSON syntax
# 2. matchKey fields exist in both configs and live-configs
# 3. matchKey values align correctly

set -e

echo "=============================================="
echo "Dual Config.json Validation Script"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

errors=0
warnings=0

echo "Step 1: Validating JSON syntax..."
echo "-------------------------------------------"

# Find and validate all config.json files in configs
echo -e "${YELLOW}Checking configs/...${NC}"
for file in $(find configs -name "config.json"); do
    if jq empty "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $file - Valid JSON"
    else
        echo -e "${RED}✗${NC} $file - Invalid JSON"
        ((errors++))
    fi
done

echo ""
echo -e "${YELLOW}Checking live-configs/...${NC}"
for file in $(find live-configs -name "config.json"); do
    if jq empty "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $file - Valid JSON"
    else
        echo -e "${RED}✗${NC} $file - Invalid JSON"
        ((errors++))
    fi
done

echo ""
echo "Step 2: Validating matchKey existence..."
echo "-------------------------------------------"

# Check matchKey in configs
echo -e "${YELLOW}Checking matchKey in configs/...${NC}"
for file in $(find configs -name "config.json"); do
    matchKey=$(jq -r '.matchKey // empty' "$file")
    if [ -n "$matchKey" ]; then
        echo -e "${GREEN}✓${NC} $file - matchKey: $matchKey"
    else
        echo -e "${RED}✗${NC} $file - Missing matchKey field"
        ((errors++))
    fi
done

echo ""
echo -e "${YELLOW}Checking matchKey in live-configs/...${NC}"
for file in $(find live-configs -name "config.json"); do
    matchKey=$(jq -r '.matchKey // empty' "$file")
    if [ -n "$matchKey" ]; then
        echo -e "${GREEN}✓${NC} $file - matchKey: $matchKey"
    else
        echo -e "${RED}✗${NC} $file - Missing matchKey field"
        ((errors++))
    fi
done

echo ""
echo "Step 3: Validating matchKey alignment..."
echo "-------------------------------------------"

# Get list of matchKeys from configs
configs_keys=$(find configs -name "config.json" -exec jq -r '.matchKey // empty' {} \; | sort)
live_keys=$(find live-configs -name "config.json" -exec jq -r '.matchKey // empty' {} \; | sort)

echo -e "${YELLOW}Checking for matching pairs...${NC}"
for key in $configs_keys; do
    if echo "$live_keys" | grep -q "^${key}$"; then
        config_file=$(find configs -name "config.json" -exec sh -c 'jq -r ".matchKey" "$1" | grep -q "^'"$key"'$" && echo "$1"' _ {} \;)
        live_file=$(find live-configs -name "config.json" -exec sh -c 'jq -r ".matchKey" "$1" | grep -q "^'"$key"'$" && echo "$1"' _ {} \;)
        echo -e "${GREEN}✓${NC} Found matching pair for matchKey: $key"
        echo "    Config:      $config_file"
        echo "    Live-Config: $live_file"
    else
        echo -e "${YELLOW}⚠${NC} No matching live-config found for matchKey: $key"
        ((warnings++))
    fi
done

echo ""
echo "Step 4: Displaying merged configuration preview..."
echo "-------------------------------------------"

for key in $configs_keys; do
    if echo "$live_keys" | grep -q "^${key}$"; then
        config_file=$(find configs -name "config.json" -exec sh -c 'jq -r ".matchKey" "$1" | grep -q "^'"$key"'$" && echo "$1"' _ {} \;)
        live_file=$(find live-configs -name "config.json" -exec sh -c 'jq -r ".matchKey" "$1" | grep -q "^'"$key"'$" && echo "$1"' _ {} \;)

        echo ""
        echo -e "${GREEN}Matched Pair: $key${NC}"
        echo "-------------------------------------------"

        echo -e "${YELLOW}From configs/${NC}"
        jq '{
            appName: .appName,
            environment: .environment,
            instance: .instance,
            replicas: .replicas,
            namespace: .namespace,
            image: .image
        }' "$config_file" 2>/dev/null || echo "Could not parse config"

        echo ""
        echo -e "${YELLOW}From live-configs/${NC}"
        jq '{
            dbConfig: .dbConfig,
            resources: .resources,
            secrets: .secrets
        }' "$live_file" 2>/dev/null || echo "Could not parse live-config"
    fi
done

echo ""
echo "=============================================="
echo "Validation Summary"
echo "=============================================="
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✓ All validations passed!${NC}"
    echo "Your dual config.json setup is ready to use."
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation completed with $warnings warning(s)${NC}"
    echo "Your setup will work, but you may have orphaned configs."
else
    echo -e "${RED}✗ Validation failed with $errors error(s) and $warnings warning(s)${NC}"
    echo "Please fix the errors before using this configuration."
    exit 1
fi

echo ""
echo "Next steps:"
echo "1. Review the merged configuration preview above"
echo "2. Apply the ApplicationSet: kubectl apply -f applicationset-dual-config.yaml"
echo "3. Check ArgoCD UI for generated applications"
