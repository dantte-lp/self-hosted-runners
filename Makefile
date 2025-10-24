.PHONY: help build install uninstall start stop restart status logs clean rebuild
.PHONY: build-buildah build-multiarch inspect push pull validate-tools

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Directories
SYSTEMD_DIR := /etc/containers/systemd
PODS_DIR := $(CURDIR)/pods

# Build tool selection (podman or buildah)
BUILD_TOOL ?= podman
# Supported architectures for multi-arch builds
PLATFORMS ?= linux/amd64,linux/arm64

# Image registry (for push/pull operations)
REGISTRY ?= localhost
IMAGE_PREFIX ?= github-runner

help: ## Show this help message
	@echo -e "$(CYAN)Self-Hosted GitHub Actions Runners$(NC)"
	@echo ""
	@echo -e "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(YELLOW)Prerequisites (Required):$(NC)"
	@echo "  - RHEL 9+ / Oracle Linux 9+ / Fedora 38+"
	@echo "  - Podman 4.4+ with quadlet support"
	@echo "  - Systemd 247+"
	@echo ""
	@echo -e "$(YELLOW)Optional Tools (Containers Ecosystem):$(NC)"
	@echo "  - Buildah - Advanced image building with multi-arch support"
	@echo "  - Skopeo  - Registry operations (inspect, push, pull, sync)"
	@echo "  - crun    - High-performance OCI runtime"
	@echo ""
	@echo -e "$(CYAN)Quick Start Examples:$(NC)"
	@echo "  make build               # Build with Podman (default)"
	@echo "  make build-buildah       # Build with Buildah"
	@echo "  make build-multiarch     # Build for amd64 and arm64"
	@echo "  make inspect             # Inspect images with Skopeo"
	@echo "  make validate-tools      # Check available containers tools"
	@echo ""

check-prereqs: ## Check system prerequisites
	@echo -e "$(CYAN)Checking prerequisites...$(NC)"
	@printf "Podman version: "
	@podman --version || (echo -e "$(RED)ERROR: Podman not found$(NC)" && exit 1)
	@printf "Systemd version: "
	@systemctl --version | head -n1 || (echo -e "$(RED)ERROR: Systemd not found$(NC)" && exit 1)
	@printf "Quadlet support: "
	@PODMAN_VERSION=$$(podman --version | awk '{print $$3}' | cut -d. -f1-2); \
	if awk "BEGIN {exit !($$PODMAN_VERSION >= 4.4)}"; then \
		echo -e "$(GREEN)OK (built into Podman $$PODMAN_VERSION)$(NC)"; \
	else \
		echo -e "$(RED)ERROR: Podman 4.4+ required$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)All prerequisites met!$(NC)"

validate-tools: ## Validate containers ecosystem tools (Buildah, Skopeo, crun)
	@echo -e "$(CYAN)Validating containers ecosystem tools...$(NC)"
	@printf "Podman: "
	@if command -v podman >/dev/null 2>&1; then \
		podman --version; \
	else \
		echo -e "$(RED)NOT FOUND$(NC)"; \
	fi
	@printf "Buildah: "
	@if command -v buildah >/dev/null 2>&1; then \
		buildah --version; \
	else \
		echo -e "$(YELLOW)NOT FOUND (optional - for advanced builds)$(NC)"; \
	fi
	@printf "Skopeo: "
	@if command -v skopeo >/dev/null 2>&1; then \
		skopeo --version; \
	else \
		echo -e "$(YELLOW)NOT FOUND (optional - for registry operations)$(NC)"; \
	fi
	@printf "crun: "
	@if command -v crun >/dev/null 2>&1; then \
		crun --version | head -n1; \
	else \
		echo -e "$(YELLOW)NOT FOUND (optional - alternative OCI runtime)$(NC)"; \
	fi
	@echo ""
	@echo -e "$(CYAN)Installation commands:$(NC)"
	@echo "  Buildah: sudo dnf install -y buildah"
	@echo "  Skopeo:  sudo dnf install -y skopeo"
	@echo "  crun:    sudo dnf install -y crun"

build: check-prereqs ## Build container images (using podman)
	@echo -e "$(CYAN)Building Debian runner image with Podman...$(NC)"
	podman build -t github-runner-debian:latest -f $(PODS_DIR)/github-runner-debian/Containerfile $(PODS_DIR)/github-runner-debian/
	@echo -e "$(CYAN)Building Oracle Linux runner image with Podman...$(NC)"
	podman build -t github-runner-oracle:latest -f $(PODS_DIR)/github-runner-oracle/Containerfile $(PODS_DIR)/github-runner-oracle/
	@echo -e "$(GREEN)Build complete!$(NC)"

build-buildah: ## Build container images using Buildah (advanced)
	@if ! command -v buildah >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Buildah not found$(NC)"; \
		echo "Install it with: sudo dnf install -y buildah"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Building Debian runner image with Buildah...$(NC)"
	buildah build --format docker --layers -t $(REGISTRY)/$(IMAGE_PREFIX)-debian:latest -f $(PODS_DIR)/github-runner-debian/Containerfile $(PODS_DIR)/github-runner-debian/
	@echo -e "$(CYAN)Building Oracle Linux runner image with Buildah...$(NC)"
	buildah build --format docker --layers -t $(REGISTRY)/$(IMAGE_PREFIX)-oracle:latest -f $(PODS_DIR)/github-runner-oracle/Containerfile $(PODS_DIR)/github-runner-oracle/
	@echo -e "$(GREEN)Buildah build complete!$(NC)"

build-multiarch: ## Build multi-architecture images using Buildah (amd64, arm64)
	@if ! command -v buildah >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Buildah not found$(NC)"; \
		echo "Install it with: sudo dnf install -y buildah"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Building multi-arch Debian runner...$(NC)"
	@echo "Platforms: $(PLATFORMS)"
	buildah build --manifest $(REGISTRY)/$(IMAGE_PREFIX)-debian:latest --platform $(PLATFORMS) -f $(PODS_DIR)/github-runner-debian/Containerfile $(PODS_DIR)/github-runner-debian/
	@echo -e "$(CYAN)Building multi-arch Oracle Linux runner...$(NC)"
	buildah build --manifest $(REGISTRY)/$(IMAGE_PREFIX)-oracle:latest --platform $(PLATFORMS) -f $(PODS_DIR)/github-runner-oracle/Containerfile $(PODS_DIR)/github-runner-oracle/
	@echo -e "$(GREEN)Multi-arch build complete!$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Push manifests to registry:$(NC)"
	@echo "  make push REGISTRY=your-registry.com"

install: check-prereqs build ## Install systemd quadlet units (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make install)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Installing systemd quadlet units...$(NC)"
	@mkdir -p $(SYSTEMD_DIR)
	install -m 644 $(PODS_DIR)/github-runner-debian/github-runner-debian.container $(SYSTEMD_DIR)/
	install -m 644 $(PODS_DIR)/github-runner-oracle/github-runner-oracle.container $(SYSTEMD_DIR)/
	@echo -e "$(CYAN)Reloading systemd daemon...$(NC)"
	systemctl daemon-reload
	@echo -e "$(GREEN)Installation complete!$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Configure environment: cp pods/shared/env.example pods/shared/.env"
	@echo "  2. Edit pods/shared/.env and set RUNNER_TOKEN"
	@echo "  3. Start runners: sudo systemctl start github-runner-debian.service github-runner-oracle.service"
	@echo "  4. Enable auto-start: sudo systemctl enable github-runner-debian.service github-runner-oracle.service"

uninstall: ## Uninstall systemd quadlet units (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make uninstall)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Stopping services...$(NC)"
	-systemctl stop github-runner-debian.service 2>/dev/null || true
	-systemctl stop github-runner-oracle.service 2>/dev/null || true
	@echo -e "$(CYAN)Disabling services...$(NC)"
	-systemctl disable github-runner-debian.service 2>/dev/null || true
	-systemctl disable github-runner-oracle.service 2>/dev/null || true
	@echo -e "$(CYAN)Removing systemd quadlet units...$(NC)"
	rm -f $(SYSTEMD_DIR)/github-runner-debian.container
	rm -f $(SYSTEMD_DIR)/github-runner-oracle.container
	@echo -e "$(CYAN)Reloading systemd daemon...$(NC)"
	systemctl daemon-reload
	@echo -e "$(GREEN)Uninstallation complete!$(NC)"

start: ## Start all runners (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make start)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Starting GitHub Actions runners...$(NC)"
	systemctl start github-runner-debian.service
	systemctl start github-runner-oracle.service
	@echo -e "$(GREEN)Runners started!$(NC)"

stop: ## Stop all runners (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make stop)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Stopping GitHub Actions runners...$(NC)"
	systemctl stop github-runner-debian.service
	systemctl stop github-runner-oracle.service
	@echo -e "$(GREEN)Runners stopped!$(NC)"

restart: ## Restart all runners (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make restart)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Restarting GitHub Actions runners...$(NC)"
	systemctl restart github-runner-debian.service
	systemctl restart github-runner-oracle.service
	@echo -e "$(GREEN)Runners restarted!$(NC)"

status: ## Check status of all runners (requires root)
	@echo -e "$(CYAN)GitHub Actions Runners Status:$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Debian Runner:$(NC)"
	@systemctl status github-runner-debian.service --no-pager || true
	@echo ""
	@echo -e "$(YELLOW)Oracle Linux Runner:$(NC)"
	@systemctl status github-runner-oracle.service --no-pager || true

logs: ## Show logs for all runners (requires root)
	@echo -e "$(CYAN)Showing logs (Ctrl+C to exit)...$(NC)"
	journalctl -u github-runner-debian.service -u github-runner-oracle.service -f

logs-debian: ## Show logs for Debian runner (requires root)
	@echo -e "$(CYAN)Debian Runner Logs (Ctrl+C to exit)...$(NC)"
	journalctl -u github-runner-debian.service -f

logs-oracle: ## Show logs for Oracle Linux runner (requires root)
	@echo -e "$(CYAN)Oracle Linux Runner Logs (Ctrl+C to exit)...$(NC)"
	journalctl -u github-runner-oracle.service -f

clean: ## Clean container images and build cache
	@echo -e "$(CYAN)Cleaning container images...$(NC)"
	-podman rmi github-runner-debian:latest 2>/dev/null || true
	-podman rmi github-runner-oracle:latest 2>/dev/null || true
	@echo -e "$(CYAN)Pruning unused images...$(NC)"
	podman image prune -f
	@echo -e "$(GREEN)Cleanup complete!$(NC)"

rebuild: clean build ## Rebuild container images from scratch

token: ## Generate GitHub runner registration token
	@echo -e "$(CYAN)Generating GitHub runner registration token...$(NC)"
	@if command -v gh >/dev/null 2>&1; then \
		gh api --method POST /repos/dantte-lp/ocserv-agent/actions/runners/registration-token --jq '.token'; \
	else \
		echo "$(RED)ERROR: GitHub CLI (gh) not installed$(NC)"; \
		echo "Install it from: https://cli.github.com/"; \
		exit 1; \
	fi

validate-env: ## Validate environment configuration
	@echo -e "$(CYAN)Validating environment configuration...$(NC)"
	@if [ ! -f "$(PODS_DIR)/shared/.env" ]; then \
		echo "$(RED)ERROR: pods/shared/.env not found$(NC)"; \
		echo "Run: cp pods/shared/env.example pods/shared/.env"; \
		exit 1; \
	fi
	@if ! grep -q "RUNNER_TOKEN=" "$(PODS_DIR)/shared/.env" || grep -q "RUNNER_TOKEN=your-token-here" "$(PODS_DIR)/shared/.env"; then \
		echo "$(YELLOW)WARNING: RUNNER_TOKEN not configured in .env$(NC)"; \
		echo "Get token with: make token"; \
	else \
		echo "$(GREEN)Environment configuration valid!$(NC)"; \
	fi

info: ## Show system information
	@echo -e "$(CYAN)System Information:$(NC)"
	@echo ""
	@echo -e "$(YELLOW)OS:$(NC)"
	@cat /etc/os-release | grep -E '^(NAME|VERSION)=' || true
	@echo ""
	@echo -e "$(YELLOW)Podman:$(NC)"
	@podman --version
	@podman info --format "{{.Host.Arch}} / {{.Host.Distribution.Distribution}} {{.Host.Distribution.Version}}"
	@echo ""
	@echo -e "$(YELLOW)Systemd:$(NC)"
	@systemctl --version | head -n1
	@echo ""
	@echo -e "$(YELLOW)Container Images:$(NC)"
	@podman images | grep -E '(REPOSITORY|github-runner)' || echo "No runner images found"
	@echo ""
	@echo -e "$(YELLOW)Running Containers:$(NC)"
	@podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E '(NAMES|github-runner)' || echo "No runner containers found"

enable: ## Enable auto-start on boot (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make enable)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Enabling auto-start on boot...$(NC)"
	systemctl enable github-runner-debian.service
	systemctl enable github-runner-oracle.service
	@echo -e "$(GREEN)Auto-start enabled!$(NC)"

disable: ## Disable auto-start on boot (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make disable)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Disabling auto-start on boot...$(NC)"
	systemctl disable github-runner-debian.service
	systemctl disable github-runner-oracle.service
	@echo -e "$(GREEN)Auto-start disabled!$(NC)"

# ════════════════════════════════════════════════════════════════════
# Skopeo Operations (Registry Management)
# ════════════════════════════════════════════════════════════════════

inspect: ## Inspect container images using Skopeo
	@if ! command -v skopeo >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Skopeo not found$(NC)"; \
		echo "Install it with: sudo dnf install -y skopeo"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Inspecting Debian runner image...$(NC)"
	@if podman images | grep -q github-runner-debian; then \
		skopeo inspect containers-storage:localhost/github-runner-debian:latest; \
	else \
		echo "$(YELLOW)Image not found: github-runner-debian:latest$(NC)"; \
	fi
	@echo ""
	@echo -e "$(CYAN)Inspecting Oracle Linux runner image...$(NC)"
	@if podman images | grep -q github-runner-oracle; then \
		skopeo inspect containers-storage:localhost/github-runner-oracle:latest; \
	else \
		echo "$(YELLOW)Image not found: github-runner-oracle:latest$(NC)"; \
	fi

push: ## Push images to registry using Skopeo (requires REGISTRY variable)
	@if ! command -v skopeo >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Skopeo not found$(NC)"; \
		echo "Install it with: sudo dnf install -y skopeo"; \
		exit 1; \
	fi
	@if [ "$(REGISTRY)" = "localhost" ]; then \
		echo "$(RED)ERROR: Please specify a remote registry$(NC)"; \
		echo "Usage: make push REGISTRY=your-registry.com"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Pushing images to $(REGISTRY)...$(NC)"
	@echo "Pushing Debian runner..."
	skopeo copy containers-storage:localhost/github-runner-debian:latest docker://$(REGISTRY)/$(IMAGE_PREFIX)-debian:latest
	@echo "Pushing Oracle Linux runner..."
	skopeo copy containers-storage:localhost/github-runner-oracle:latest docker://$(REGISTRY)/$(IMAGE_PREFIX)-oracle:latest
	@echo -e "$(GREEN)Push complete!$(NC)"
	@echo ""
	@echo "Images available at:"
	@echo "  - $(REGISTRY)/$(IMAGE_PREFIX)-debian:latest"
	@echo "  - $(REGISTRY)/$(IMAGE_PREFIX)-oracle:latest"

pull: ## Pull images from registry using Skopeo (requires REGISTRY variable)
	@if ! command -v skopeo >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Skopeo not found$(NC)"; \
		echo "Install it with: sudo dnf install -y skopeo"; \
		exit 1; \
	fi
	@if [ "$(REGISTRY)" = "localhost" ]; then \
		echo "$(RED)ERROR: Please specify a remote registry$(NC)"; \
		echo "Usage: make pull REGISTRY=your-registry.com"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Pulling images from $(REGISTRY)...$(NC)"
	@echo "Pulling Debian runner..."
	skopeo copy docker://$(REGISTRY)/$(IMAGE_PREFIX)-debian:latest containers-storage:localhost/github-runner-debian:latest
	@echo "Pulling Oracle Linux runner..."
	skopeo copy docker://$(REGISTRY)/$(IMAGE_PREFIX)-oracle:latest containers-storage:localhost/github-runner-oracle:latest
	@echo -e "$(GREEN)Pull complete!$(NC)"

sync: ## Synchronize images between registries using Skopeo
	@if ! command -v skopeo >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Skopeo not found$(NC)"; \
		echo "Install it with: sudo dnf install -y skopeo"; \
		exit 1; \
	fi
	@if [ -z "$(SRC_REGISTRY)" ] || [ -z "$(DST_REGISTRY)" ]; then \
		echo "$(RED)ERROR: Please specify source and destination registries$(NC)"; \
		echo "Usage: make sync SRC_REGISTRY=source.com DST_REGISTRY=dest.com"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Syncing images from $(SRC_REGISTRY) to $(DST_REGISTRY)...$(NC)"
	skopeo sync --src docker --dest docker $(SRC_REGISTRY)/$(IMAGE_PREFIX)-debian:latest $(DST_REGISTRY)/$(IMAGE_PREFIX)-debian:latest
	skopeo sync --src docker --dest docker $(SRC_REGISTRY)/$(IMAGE_PREFIX)-oracle:latest $(DST_REGISTRY)/$(IMAGE_PREFIX)-oracle:latest
	@echo -e "$(GREEN)Sync complete!$(NC)"
