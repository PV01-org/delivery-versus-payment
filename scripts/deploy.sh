#!/usr/bin/env bash
set -euo pipefail

# env vars
if [ -f .env ]; then
  set -a        # auto-export vars
  source .env
  set +a
fi

# Validate
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "Error: PRIVATE_KEY not set"
  exit 1
fi

# Scope
NETWORKS=(sepolia)
#NETWORKS=(sepolia arbsepolia fuji polygon avalanche ethereum)

for NET in "${NETWORKS[@]}"; do
  echo "Deploying DVP to $NET"
  forge script script/DeployDvp.s.sol:Deploy \
    --rpc-url "$NET" \
    --broadcast \
    --verify \
    --private-key "$PRIVATE_KEY"

  echo "Deploying DVP Helper to $NET"
  forge script script/DeployDvpHelper.s.sol:Deploy \
    --rpc-url "$NET" \
    --broadcast \
    --verify \
    --private-key "$PRIVATE_KEY"
done
