.PHONY: help build install uninstall start stop restart status logs clean rebuild

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

help: ## Show this help message
	@echo "$(CYAN)Self-Hosted GitHub Actions Runners$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Prerequisites:$(NC)"
	@echo "  - RHEL 9+ / Oracle Linux 9+ / Fedora 38+"
	@echo "  - Podman 4.4+ with quadlet support"
	@echo "  - Systemd 247+"
	@echo ""

check-prereqs: ## Check system prerequisites
	@echo "$(CYAN)Checking prerequisites...$(NC)"
	@echo -n "Podman version: "
	@podman --version || (echo "$(RED)ERROR: Podman not found$(NC)" && exit 1)
	@echo -n "Systemd version: "
	@systemctl --version | head -n1 || (echo "$(RED)ERROR: Systemd not found$(NC)" && exit 1)
	@echo -n "Quadlet support: "
	@if ls /usr/lib/systemd/system-generators/*quadlet* >/dev/null 2>&1; then \
		echo "$(GREEN)OK$(NC)"; \
	else \
		echo "$(RED)ERROR: Quadlet not found$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)All prerequisites met!$(NC)"

build: check-prereqs ## Build container images
	@echo "$(CYAN)Building Debian runner image...$(NC)"
	podman build -t github-runner-debian:latest -f $(PODS_DIR)/github-runner-debian/Containerfile $(PODS_DIR)/github-runner-debian/
	@echo "$(CYAN)Building Oracle Linux runner image...$(NC)"
	podman build -t github-runner-oracle:latest -f $(PODS_DIR)/github-runner-oracle/Containerfile $(PODS_DIR)/github-runner-oracle/
	@echo "$(GREEN)Build complete!$(NC)"

install: check-prereqs build ## Install systemd quadlet units (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make install)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Installing systemd quadlet units...$(NC)"
	@mkdir -p $(SYSTEMD_DIR)
	install -m 644 $(PODS_DIR)/github-runner-debian/github-runner-debian.container $(SYSTEMD_DIR)/
	install -m 644 $(PODS_DIR)/github-runner-oracle/github-runner-oracle.container $(SYSTEMD_DIR)/
	@echo "$(CYAN)Reloading systemd daemon...$(NC)"
	systemctl daemon-reload
	@echo "$(GREEN)Installation complete!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Configure environment: cp pods/shared/env.example pods/shared/.env"
	@echo "  2. Edit pods/shared/.env and set RUNNER_TOKEN"
	@echo "  3. Start runners: sudo systemctl start github-runner-debian.service github-runner-oracle.service"
	@echo "  4. Enable auto-start: sudo systemctl enable github-runner-debian.service github-runner-oracle.service"

uninstall: ## Uninstall systemd quadlet units (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make uninstall)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Stopping services...$(NC)"
	-systemctl stop github-runner-debian.service 2>/dev/null || true
	-systemctl stop github-runner-oracle.service 2>/dev/null || true
	@echo "$(CYAN)Disabling services...$(NC)"
	-systemctl disable github-runner-debian.service 2>/dev/null || true
	-systemctl disable github-runner-oracle.service 2>/dev/null || true
	@echo "$(CYAN)Removing systemd quadlet units...$(NC)"
	rm -f $(SYSTEMD_DIR)/github-runner-debian.container
	rm -f $(SYSTEMD_DIR)/github-runner-oracle.container
	@echo "$(CYAN)Reloading systemd daemon...$(NC)"
	systemctl daemon-reload
	@echo "$(GREEN)Uninstallation complete!$(NC)"

start: ## Start all runners (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make start)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Starting GitHub Actions runners...$(NC)"
	systemctl start github-runner-debian.service
	systemctl start github-runner-oracle.service
	@echo "$(GREEN)Runners started!$(NC)"

stop: ## Stop all runners (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make stop)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Stopping GitHub Actions runners...$(NC)"
	systemctl stop github-runner-debian.service
	systemctl stop github-runner-oracle.service
	@echo "$(GREEN)Runners stopped!$(NC)"

restart: ## Restart all runners (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make restart)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Restarting GitHub Actions runners...$(NC)"
	systemctl restart github-runner-debian.service
	systemctl restart github-runner-oracle.service
	@echo "$(GREEN)Runners restarted!$(NC)"

status: ## Check status of all runners (requires root)
	@echo "$(CYAN)GitHub Actions Runners Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)Debian Runner:$(NC)"
	@systemctl status github-runner-debian.service --no-pager || true
	@echo ""
	@echo "$(YELLOW)Oracle Linux Runner:$(NC)"
	@systemctl status github-runner-oracle.service --no-pager || true

logs: ## Show logs for all runners (requires root)
	@echo "$(CYAN)Showing logs (Ctrl+C to exit)...$(NC)"
	journalctl -u github-runner-debian.service -u github-runner-oracle.service -f

logs-debian: ## Show logs for Debian runner (requires root)
	@echo "$(CYAN)Debian Runner Logs (Ctrl+C to exit)...$(NC)"
	journalctl -u github-runner-debian.service -f

logs-oracle: ## Show logs for Oracle Linux runner (requires root)
	@echo "$(CYAN)Oracle Linux Runner Logs (Ctrl+C to exit)...$(NC)"
	journalctl -u github-runner-oracle.service -f

clean: ## Clean container images and build cache
	@echo "$(CYAN)Cleaning container images...$(NC)"
	-podman rmi github-runner-debian:latest 2>/dev/null || true
	-podman rmi github-runner-oracle:latest 2>/dev/null || true
	@echo "$(CYAN)Pruning unused images...$(NC)"
	podman image prune -f
	@echo "$(GREEN)Cleanup complete!$(NC)"

rebuild: clean build ## Rebuild container images from scratch

token: ## Generate GitHub runner registration token
	@echo "$(CYAN)Generating GitHub runner registration token...$(NC)"
	@if command -v gh >/dev/null 2>&1; then \
		gh api --method POST /repos/dantte-lp/ocserv-agent/actions/runners/registration-token --jq '.token'; \
	else \
		echo "$(RED)ERROR: GitHub CLI (gh) not installed$(NC)"; \
		echo "Install it from: https://cli.github.com/"; \
		exit 1; \
	fi

validate-env: ## Validate environment configuration
	@echo "$(CYAN)Validating environment configuration...$(NC)"
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
	@echo "$(CYAN)System Information:$(NC)"
	@echo ""
	@echo "$(YELLOW)OS:$(NC)"
	@cat /etc/os-release | grep -E '^(NAME|VERSION)=' || true
	@echo ""
	@echo "$(YELLOW)Podman:$(NC)"
	@podman --version
	@podman info --format "{{.Host.Arch}} / {{.Host.Distribution.Distribution}} {{.Host.Distribution.Version}}"
	@echo ""
	@echo "$(YELLOW)Systemd:$(NC)"
	@systemctl --version | head -n1
	@echo ""
	@echo "$(YELLOW)Container Images:$(NC)"
	@podman images | grep -E '(REPOSITORY|github-runner)' || echo "No runner images found"
	@echo ""
	@echo "$(YELLOW)Running Containers:$(NC)"
	@podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E '(NAMES|github-runner)' || echo "No runner containers found"

enable: ## Enable auto-start on boot (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make enable)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Enabling auto-start on boot...$(NC)"
	systemctl enable github-runner-debian.service
	systemctl enable github-runner-oracle.service
	@echo "$(GREEN)Auto-start enabled!$(NC)"

disable: ## Disable auto-start on boot (requires root)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)ERROR: This target must be run as root (use sudo make disable)$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Disabling auto-start on boot...$(NC)"
	systemctl disable github-runner-debian.service
	systemctl disable github-runner-oracle.service
	@echo "$(GREEN)Auto-start disabled!$(NC)"
