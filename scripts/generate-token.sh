#!/bin/bash

# ==============================================================================
# generate-token.sh - Generate GitHub Actions runner registration token
# ==============================================================================
#
# This script generates a fresh registration token for GitHub Actions runners.
# Tokens expire after 1 hour, so you need to generate a new one when:
#   - Starting runners for the first time
#   - Restarting runners after the token expired
#   - Re-registering runners
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Appropriate permissions on the repository
#
# Usage:
#   ./scripts/generate-token.sh
#   RUNNER_TOKEN=$(./scripts/generate-token.sh) make start
#
# ==============================================================================

set -e

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Repository (change if needed)
REPO_OWNER="dantte-lp"
REPO_NAME="ocserv-agent"

echo -e "${CYAN}GitHub Actions Runner Token Generator${NC}"
echo ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}ERROR: GitHub CLI (gh) is not installed${NC}"
    echo ""
    echo "Install it from: https://cli.github.com/"
    echo ""
    echo "On RHEL/Oracle Linux:"
    echo "  sudo dnf install gh"
    echo ""
    echo "On Debian/Ubuntu:"
    echo "  sudo apt install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}ERROR: GitHub CLI is not authenticated${NC}"
    echo ""
    echo "Run: gh auth login"
    exit 1
fi

echo -e "${YELLOW}Generating runner registration token for ${REPO_OWNER}/${REPO_NAME}...${NC}"

# Generate token
TOKEN=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/registration-token" \
    --jq '.token' 2>&1)

# Check if token generation failed
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to generate token${NC}"
    echo ""
    echo "Response: $TOKEN"
    echo ""
    echo "Common causes:"
    echo "  - Insufficient permissions (need admin access or manage runner permission)"
    echo "  - Repository does not exist"
    echo "  - Network connectivity issues"
    exit 1
fi

# Validate token (should be non-empty and alphanumeric)
if [ -z "$TOKEN" ] || ! [[ "$TOKEN" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo -e "${RED}ERROR: Invalid token received${NC}"
    echo "Token: $TOKEN"
    exit 1
fi

echo -e "${GREEN}✅ Token generated successfully!${NC}"
echo ""
echo -e "${YELLOW}Token:${NC}"
echo "$TOKEN"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update pods/shared/.env:"
echo "   RUNNER_TOKEN=$TOKEN"
echo ""
echo "2. Start runners:"
echo "   sudo make start"
echo ""
echo -e "${YELLOW}Note: Token expires in 1 hour${NC}"

# Also output just the token (for scripting)
# This allows: RUNNER_TOKEN=$(./scripts/generate-token.sh | tail -1)
# But we'll make it easier by checking if stdout is a terminal
if [ -t 1 ]; then
    # Terminal output (human-readable)
    :
else
    # Pipe/redirect (just output token)
    echo "$TOKEN"
fi
