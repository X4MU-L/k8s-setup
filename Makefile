# Configuration
PROJECT_NAME ?= k8s-installer
LOCAL_DIR = /usr/local
INSTALL_DIR = $(LOCAL_DIR)/lib/$(PROJECT_NAME)
LOG_DIR = /var/log/$(PROJECT_NAME)
WRAPPER := $(LOCAL_DIR)/bin/$(PROJECT_NAME)

.PHONY: all install uninstall clean

all: check-deps check-root
check-root:
	@echo "Checking root privileges..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "This script must be run as root. Please use sudo make install."; \
		exit 1; \
    fi

install: check-root
	@echo "Installing $(PROJECT_NAME)..."
# Create directories
	@mkdir -p $(INSTALL_DIR)
	@mkdir -p $(LOCAL_DIR)/bin
	@mkdir -p $(LOG_DIR)

# Copy and process source files
	@cp -r src utils $(INSTALL_DIR)/ \
	|| { echo "Failed to copy files. Please run on a Linux machine."; \
	     echo "Cleaning up..."; \
	     rm -rf $(INSTALL_DIR); \
	     rm -rf $(LOG_DIR); \
	     exit 1; }

	
# create wrapper script
	@echo "Creating wrapper script..."
	@tmpfile="$$(mktemp)"; \
	echo '#!/bin/bash' > $$tmpfile; \
	echo "\"$(INSTALL_DIR)/src/main.sh\" \"\$$@\"" >> $$tmpfile; \
	if ! cmp -s $$tmpfile "$(WRAPPER)"; then \
		cp $$tmpfile "$(WRAPPER)"; \
		chmod +x "$(WRAPPER)"; \
		echo "Wrapper script created at $(WRAPPER)"; \
	else \
		echo "Wrapper script is already up to date."; \
	fi; \
	rm -f $$tmpfile 
# Set permissions
	@chmod +x "$(INSTALL_DIR)/src/main.sh"
	@chmod 755 $(LOG_DIR)

# Setup logrotate
	@echo "Setting up logrotate configuration..."
	@if ! test -f "/etc/logrotate.d/$(PROJECT_NAME)"; then \
		printf "%s\n" "$(LOG_DIR)/*.log {" \
		"    daily" \
		"    rotate 7" \
		"    compress" \
		"    delaycompress" \
		"    missingok" \
		"    notifempty" \
		"    create 0644 root root" \
		"}" | tee "/etc/logrotate.d/$(PROJECT_NAME)" > /dev/null; \
		echo "Logrotate configuration created."; \
	else \
		echo "Logrotate configuration already exists."; \
	fi

uninstall: check-root
	@echo "Uninstalling $(PROJECT_NAME)..."
	@rm -f "/etc/logrotate.d/$(PROJECT_NAME)"
	@rm -f "$(WRAPPER)"
	@rm -rf "$(INSTALL_DIR)"
	@rm -rf "$(LOG_DIR)"
	@echo "Uninstallation complete!"

clean:
	@echo "Cleaning build artifacts..."
	@rm -f *~