#!/usr/bin/env bash

# =============================================================================
# Get Available Intric Helm Chart Versions
# =============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Fetches available versions of the Intric Helm chart from GitHub Container Registry.

OPTIONS:
    -t, --token TOKEN    GitHub Personal Access Token (required)
    -h, --help          Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN        Alternative way to provide the token

EXAMPLES:
    # Using flag
    $0 --token ghp_yourTokenHere
    
    # Using environment variable
    export GITHUB_TOKEN=ghp_yourTokenHere
    $0

EOF
}

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token is required."
    echo "Provide it via --token flag or GITHUB_TOKEN environment variable."
    echo "Use --help for more information."
    exit 1
fi

curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  https://api.github.com/orgs/inoolabs/packages/container/charts%2Fintric-helm/versions \
  | jq -r '.[].metadata.container.tags[]' 2>/dev/null | sort -Vr