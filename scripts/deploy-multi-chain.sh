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

# Supported networks list — edit here to add/remove supported networks.
# Network names need to match those defined in foundry.toml
SUPPORTED_NETWORKS=(
  "sepolia"
  "arbsepolia"
  "polygon"
  "fuji"
  "avalanche"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [-n NETWORK]...

Options:
  -n NETWORK   Specify a network to deploy to. Can be provided multiple times.
  -h           Show this help message.

Behavior:
  - If no -n is provided, the script deploys to ALL supported networks.
  - If any provided network is not supported, the script exits with an error,
    listing the invalid selections and all supported networks.

Supported networks:
  ${SUPPORTED_NETWORKS[*]}
EOF
}

# Convert SUPPORTED_NETWORKS array to an associative set for O(1) lookup
declare -A SUPPORTED_SET=()
for net in "${SUPPORTED_NETWORKS[@]}"; do
  SUPPORTED_SET["$net"]=1
done

# Parse arguments
SELECTED_NETWORKS=()
if [[ $# -gt 0 ]]; then
  while getopts ":n:h" opt; do
    case ${opt} in
      n)
        SELECTED_NETWORKS+=("${OPTARG}")
        ;;
      h)
        usage
        exit 0
        ;;
      :)
        echo "Error: Option -$OPTARG requires an argument." >&2
        echo >&2
        usage >&2
        exit 2
        ;;
      \?)
        echo "Error: Invalid option -$OPTARG" >&2
        echo >&2
        usage >&2
        exit 2
        ;;
    esac
  done
  shift $((OPTIND - 1))
fi

# Default: if no -n provided, deploy to all supported networks
if [[ ${#SELECTED_NETWORKS[@]} -eq 0 ]]; then
  SELECTED_NETWORKS=("${SUPPORTED_NETWORKS[@]}")
fi

# Validate selected networks
INVALID_NETWORKS=()
for sel in "${SELECTED_NETWORKS[@]}"; do
  if [[ -z "${SUPPORTED_SET[$sel]:-}" ]]; then
    INVALID_NETWORKS+=("$sel")
  fi
done

if [[ ${#INVALID_NETWORKS[@]} -gt 0 ]]; then
  echo "Error: One or more selected networks are not supported." >&2
  echo "Unsupported: ${INVALID_NETWORKS[*]}" >&2
  echo "Supported:   ${SUPPORTED_NETWORKS[*]}" >&2
  exit 1
fi

# Deployment function
deploy_to_network() {
  local network="$1"
  echo "Deploying to $network ..."
  forge script script/DeployDvp.s.sol:Deploy \
    --rpc-url "$network" \
    --broadcast \
    --verify \
    --private-key "$PRIVATE_KEY"

  echo "Deploying DVP Helper to $NET"
  forge script script/DeployDvpHelper.s.sol:Deploy \
    --rpc-url "$network" \
    --broadcast \
    --verify \
    --private-key "$PRIVATE_KEY"
}

# Deploy to each validated network
for net in "${SELECTED_NETWORKS[@]}"; do
  deploy_to_network "$net"
  echo "Done: $net"
  echo
done

echo "All deployments completed successfully."
