# Makefile for tmux-claude-ext
# Created: 2025-08-07

.PHONY: all install uninstall test clean help check lint permissions dev

# Variables
PREFIX ?= $(HOME)/.tmux/plugins
INSTALL_DIR = $(PREFIX)/tmux-claude-ext
STATE_DIR = /tmp/tmux-claude
SHELL = /bin/bash

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
NC = \033[0m # No Color

# Default target
all: check permissions
	@echo -e "$(GREEN)✓ tmux-claude-ext is ready to install$(NC)"
	@echo "Run 'make install' to install the extension"

# Help target
help:
	@echo "tmux-claude-ext Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Check dependencies and prepare for installation (default)"
	@echo "  install       - Install tmux-claude-ext to ~/.tmux/plugins/"
	@echo "  global-install - Install + create global commands (claude-ctl, etc.)"
	@echo "  uninstall     - Remove tmux-claude-ext"
	@echo "  global-uninstall - Remove everything including global commands"
	@echo "  test        - Run full test suite"
	@echo "  test-unit   - Run unit tests only"
	@echo "  test-integration - Run integration tests only"
	@echo "  test-coverage - Run tests with coverage report"
	@echo "  check       - Check dependencies"
	@echo "  lint        - Check shell scripts for issues"
	@echo "  permissions - Set correct file permissions"
	@echo "  dev         - Development mode (install from current directory)"
	@echo "  clean       - Clean temporary files and logs"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX      - Installation prefix (default: ~/.tmux/plugins)"
	@echo ""
	@echo "Examples:"
	@echo "  make install           - Standard installation"
	@echo "  make PREFIX=/usr/local install - Custom installation path"
	@echo "  make test              - Run test suite"

# Check dependencies
check:
	@echo "Checking dependencies..."
	@command -v tmux >/dev/null 2>&1 || { echo -e "$(RED)✗ tmux is not installed$(NC)"; exit 1; }
	@command -v bash >/dev/null 2>&1 || { echo -e "$(RED)✗ bash is not installed$(NC)"; exit 1; }
	@echo -e "$(GREEN)✓ All dependencies satisfied$(NC)"
	@echo -n "tmux version: "
	@tmux -V

# Set permissions
permissions:
	@echo "Setting file permissions..."
	@chmod +x bin/* 2>/dev/null || true
	@chmod +x scripts/*.sh 2>/dev/null || true
	@chmod +x tests/*.sh 2>/dev/null || true
	@echo -e "$(GREEN)✓ Permissions set$(NC)"

# Install (local to ~/.tmux/plugins)
install: check permissions
	@echo "Installing tmux-claude-ext..."
	@scripts/install.sh
	@echo -e "$(GREEN)✓ Installation complete$(NC)"

# Global install - creates system-wide commands
global-install: install
	@echo "Installing global commands..."
	@sudo mkdir -p /usr/local/bin
	@sudo ln -sf ~/.tmux/plugins/tmux-claude-ext/bin/tmux-claude-monitor /usr/local/bin/claude-monitor
	@sudo ln -sf ~/.tmux/plugins/tmux-claude-ext/bin/tmux-claude-ctl /usr/local/bin/claude-ctl
	@sudo ln -sf ~/.tmux/plugins/tmux-claude-ext/bin/tmux-claude-hook /usr/local/bin/claude-hook
	@echo -e "$(GREEN)✓ Global commands installed$(NC)"
	@echo ""
	@echo "Available commands:"
	@echo "  claude-ctl         - Main control utility"
	@echo "  claude-monitor     - Monitor daemon control"  
	@echo "  claude-hook        - Hook handler (internal use)"
	@echo ""
	@echo "Quick commands:"
	@echo "  claude-ctl add     - Add current pane to monitoring"
	@echo "  claude-ctl status  - Show monitoring status"
	@echo "  claude-ctl goto    - Jump to pane needing attention"
	@echo "  claude-ctl clear   - Clear alerts"

# Uninstall
uninstall:
	@echo "Uninstalling tmux-claude-ext..."
	@scripts/uninstall.sh
	@echo -e "$(GREEN)✓ Uninstallation complete$(NC)"

# Global uninstall - removes system-wide commands
global-uninstall: uninstall
	@echo "Removing global commands..."
	@sudo rm -f /usr/local/bin/claude-monitor
	@sudo rm -f /usr/local/bin/claude-ctl
	@sudo rm -f /usr/local/bin/claude-hook
	@echo -e "$(GREEN)✓ Global commands removed$(NC)"

# Development mode - symlink instead of copy
dev: check permissions
	@echo "Setting up development environment..."
	@mkdir -p $(INSTALL_DIR)
	@ln -sf $(PWD)/bin $(INSTALL_DIR)/bin
	@ln -sf $(PWD)/lib $(INSTALL_DIR)/lib
	@ln -sf $(PWD)/conf $(INSTALL_DIR)/conf
	@echo -e "$(GREEN)✓ Development links created$(NC)"
	@echo "Note: Changes to source files will be immediately reflected"

# Run tests
test: permissions
	@echo "Running test suite..."
	@chmod +x tests/*.sh 2>/dev/null || true
	@if [ -f tests/test_runner.sh ]; then \
		bash tests/test_runner.sh; \
	elif [ -d tests ] && [ -n "$$(ls -A tests/*.sh 2>/dev/null)" ]; then \
		for test in tests/*.sh; do \
			echo "Running $$(basename $$test)..."; \
			bash $$test || exit 1; \
		done; \
		echo -e "$(GREEN)✓ All tests passed$(NC)"; \
	else \
		echo -e "$(YELLOW)⚠ No tests found$(NC)"; \
	fi

# Run only unit tests
test-unit: permissions
	@echo "Running unit tests..."
	@chmod +x tests/*.sh 2>/dev/null || true
	@if [ -f tests/test_runner.sh ]; then \
		bash tests/test_runner.sh pattern_detection.sh state_management.sh fixtures.sh; \
	else \
		echo -e "$(YELLOW)⚠ Test runner not found$(NC)"; \
	fi

# Run only integration tests
test-integration: permissions
	@echo "Running integration tests..."
	@chmod +x tests/*.sh 2>/dev/null || true
	@if [ -f tests/test_runner.sh ]; then \
		bash tests/test_runner.sh tmux_integration.sh; \
	else \
		echo -e "$(YELLOW)⚠ Test runner not found$(NC)"; \
	fi

# Run tests with coverage (requires bashcov)
test-coverage: permissions
	@echo "Running tests with coverage..."
	@if command -v bashcov &>/dev/null; then \
		bashcov tests/test_runner.sh; \
	else \
		echo -e "$(YELLOW)⚠ bashcov not installed. Install with: gem install bashcov$(NC)"; \
		$(MAKE) test; \
	fi

# Lint shell scripts
lint:
	@echo "Linting shell scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -name "*.sh" -type f -exec shellcheck {} \; && \
		find bin -type f -exec shellcheck {} \; && \
		echo -e "$(GREEN)✓ No linting issues found$(NC)"; \
	else \
		echo -e "$(YELLOW)⚠ shellcheck not installed - skipping lint$(NC)"; \
		echo "Install shellcheck for shell script linting"; \
	fi

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	@rm -rf $(STATE_DIR)
	@find . -name "*.bak" -delete
	@find . -name "*~" -delete
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@echo -e "$(GREEN)✓ Cleaned temporary files$(NC)"

# Monitor control shortcuts
start:
	@bin/tmux-claude-monitor start

stop:
	@bin/tmux-claude-monitor stop

restart:
	@bin/tmux-claude-monitor restart

status:
	@bin/tmux-claude-ctl status

# Package for distribution
dist: clean
	@echo "Creating distribution package..."
	@mkdir -p dist
	@tar czf dist/tmux-claude-ext-$(shell date +%Y%m%d).tar.gz \
		--exclude=dist \
		--exclude=.git \
		--exclude=.gitignore \
		--exclude=*.swp \
		--exclude=.DS_Store \
		bin lib conf scripts tests Makefile README.md CLAUDE.md
	@echo -e "$(GREEN)✓ Distribution package created in dist/$(NC)"

# Watch for changes during development
watch:
	@echo "Watching for changes (press Ctrl+C to stop)..."
	@while true; do \
		inotifywait -r -e modify,create,delete bin lib conf 2>/dev/null || \
		fswatch -r bin lib conf 2>/dev/null || \
		{ echo -e "$(RED)✗ No file watcher available (install inotify-tools or fswatch)$(NC)"; exit 1; }; \
		echo -e "$(YELLOW)Files changed - running tests...$(NC)"; \
		make test; \
	done

.SILENT: help
