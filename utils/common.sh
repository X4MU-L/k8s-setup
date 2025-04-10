#!/usr/bin/env bash

# Common utility functions
#
# This script contains shared utility functions used across the Kubernetes setup process.
# The functions include:
# - General-purpose helper functions to streamline repetitive tasks.
# - Logging utilities for consistent and readable output.
# - Validation functions to ensure prerequisites are met.
# - File and directory management utilities for handling configuration files.
#
# Author: Chukwuebuka Okoli
# Email: okolisamuel21@gmail.com
# URL: https://github.com/X4MU-L

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logger function
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
    case $level in
        SUCCESS)
        echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message"
        ;;
        INFO)
        echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
        ;;
        WARN)
        echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
        ;;
        ERROR)
        echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
        ;;
        *)
        echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message"
        ;;
    esac
  
  # Log to file if LOG_DIR exists
    if [ -n "${LOG_DIR:-}" ] && [ -d "$LOG_DIR" ]; then
        echo "[$level] $timestamp - $message" >> "$LOG_DIR/k8s-installer.log"
    fi

    if [ "${DEBUG:-false}" = true ]; then
        echo "[$level] $timestamp - $message"
    fi
}

# Check if running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    log ERROR "This script must be run as root or with sudo"
    exit 1
  fi
  log INFO "Running with root privileges"
}

# Function to show help message
# Display help information
show_help() {
    cat << EOF
  Kubernetes Cluster Setup Utility

  Usage: sudo ./k8s-setup-utility.sh [OPTIONS]

  Options:
    --control-plane              Configure as control plane node
    --worker                     Configure as worker node
    --k8s-version=VERSION        Kubernetes version to install (default: 1.32.3)
    --cni=PLUGIN                 CNI plugin (cilium or calico, default: cilium)
    --cni-version=VERSION        CNI plugin version (default: v1.17.2)
    --pod-network-cidr=CIDR      Pod network CIDR (default: 10.0.0.0/8)
    --control-plane-endpoint=EP  Control plane endpoint address
    --join-token=TOKEN           Join token for worker nodes
    --help                       Display this help message

  Example:
    # Setup control plane:
    sudo ./k8s-setup-utility.sh --control-plane --k8s-version=1.32.3 --cni=cilium
    
    # Setup worker node:
    sudo ./k8s-setup-utility.sh --worker --join-token="kubeadm join..."
EOF
}

# Perform cleanup on script exit
cleanup() {
  log INFO "Performing cleanup"
  # Add cleanup tasks if needed
  
}
