#!/bin/bash

# ==============================================================================
# install.sh - Install GitHub Actions runners as systemd services
# ==============================================================================
#
# This script installs systemd quadlet files for GitHub Actions runners.
# It must be run as root (or with sudo).
#
# Usage:
#   sudo ./scripts/install.sh
#   sudo make install  # Alternative using Makefile
#
# ==============================================================================

set -e

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="/etc/containers/systemd"

echo -e "${CYAN}GitHub Actions Runner Installation${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Use: sudo ./scripts/install.sh"
    exit 1
fi

# Check if Podman is installed
if ! command -v podman &> /dev/null; then
    echo -e "${RED}ERROR: Podman is not installed${NC}"
    echo ""
    echo "Install Podman first:"
    echo "  sudo dnf install podman  # RHEL/Oracle Linux"
    echo "  sudo apt install podman  # Debian/Ubuntu"
    exit 1
fi

# Check Podman version (need 4.4+ for quadlets)
PODMAN_VERSION=$(podman --version | awk '{print $3}')
echo -e "${YELLOW}Podman version: $PODMAN_VERSION${NC}"

# Check if systemd supports quadlets
if ! ls /usr/lib/systemd/system-generators/*quadlet* &> /dev/null; then
    echo -e "${RED}ERROR: Systemd quadlet support not found${NC}"
    echo ""
    echo "Quadlets require:"
    echo "  - Podman 4.4+"
    echo "  - Systemd 247+"
    echo "  - RHEL 9+, Oracle Linux 9+, or Fedora 38+"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites met${NC}"
echo ""

# Build container images
echo -e "${CYAN}Building container images...${NC}"

echo -e "${YELLOW}Building Debian runner image...${NC}"
podman build \
    -t github-runner-debian:latest \
    -f "$PROJECT_ROOT/pods/github-runner-debian/Containerfile" \
    "$PROJECT_ROOT/pods/github-runner-debian/"

echo -e "${YELLOW}Building Oracle Linux runner image...${NC}"
podman build \
    -t github-runner-oracle:latest \
    -f "$PROJECT_ROOT/pods/github-runner-oracle/Containerfile" \
    "$PROJECT_ROOT/pods/github-runner-oracle/"

echo -e "${GREEN}✅ Images built successfully${NC}"
echo ""

# Create systemd directory if it doesn't exist
echo -e "${CYAN}Installing systemd quadlet units...${NC}"
mkdir -p "$SYSTEMD_DIR"

# Install quadlet files
echo -e "${YELLOW}Installing github-runner-debian.container...${NC}"
install -m 644 \
    "$PROJECT_ROOT/pods/github-runner-debian/github-runner-debian.container" \
    "$SYSTEMD_DIR/github-runner-debian.container"

echo -e "${YELLOW}Installing github-runner-oracle.container...${NC}"
install -m 644 \
    "$PROJECT_ROOT/pods/github-runner-oracle/github-runner-oracle.container" \
    "$SYSTEMD_DIR/github-runner-oracle.container"

echo -e "${GREEN}✅ Quadlet files installed${NC}"
echo ""

# Reload systemd daemon
echo -e "${CYAN}Reloading systemd daemon...${NC}"
systemctl daemon-reload

echo -e "${GREEN}✅ Systemd daemon reloaded${NC}"
echo ""

# Check if services are recognized
echo -e "${CYAN}Verifying services...${NC}"
if systemctl list-unit-files | grep -q "github-runner-debian.service"; then
    echo -e "${GREEN}✅ github-runner-debian.service registered${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: github-runner-debian.service not found${NC}"
fi

if systemctl list-unit-files | grep -q "github-runner-oracle.service"; then
    echo -e "${GREEN}✅ github-runner-oracle.service registered${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: github-runner-oracle.service not found${NC}"
fi

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Configure environment:"
echo "   cp $PROJECT_ROOT/pods/shared/env.example $PROJECT_ROOT/pods/shared/.env"
echo "   vi $PROJECT_ROOT/pods/shared/.env  # Set RUNNER_TOKEN"
echo ""
echo "2. Generate GitHub runner token:"
echo "   $PROJECT_ROOT/scripts/generate-token.sh"
echo ""
echo "3. Start runners:"
echo "   sudo systemctl start github-runner-debian.service"
echo "   sudo systemctl start github-runner-oracle.service"
echo ""
echo "4. Enable auto-start on boot:"
echo "   sudo systemctl enable github-runner-debian.service"
echo "   sudo systemctl enable github-runner-oracle.service"
echo ""
echo "5. Check status:"
echo "   sudo systemctl status github-runner-debian.service"
echo "   sudo systemctl status github-runner-oracle.service"
echo ""
echo -e "${CYAN}Enjoy your self-hosted GitHub Actions runners!${NC}"
