#!/usr/bin/env bash

# Detection utility functions
#
# This script contains utility functions for detecting the system environment
# to ensure compatibility with a Kubernetes setup. The functions include:
# - Detecting the operating system and distribution.
# - Identifying the init system and cgroup version.
# - Checking for required ports to avoid conflicts.
#
# Author: Chukwuebuka Okoli
# Email: okolisamuel21@gmail.com
# URL: https://github.com/X4MU-L

# Detect OS and distribution
detect_os_and_arch() {
  log INFO "Detecting operating system"
  
  OS=$(uname -s)
  if [ "$OS" != "Linux" ]; then
    log ERROR "This script only supports Linux operating systems"
    exit 1
  fi
  
  # Detect distribution
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_DISTRO=$ID
    OS_VERSION=$VERSION_ID
    log INFO "Detected distribution: $OS_DISTRO $OS_VERSION"
  else
    log ERROR "Cannot detect Linux distribution"
    exit 1
  fi
  
  # Check for supported distributions
  case $OS_DISTRO in
    ubuntu|debian)
      log INFO "Running on supported distribution: $OS_DISTRO $OS_VERSION"
      ;;
    *)
      log WARN "Unsupported distribution: $OS_DISTRO. This script is designed for Ubuntu/Debian"
      log WARN "Continuing but may encounter issues..."
      ;;
  esac

  # Detect architecture
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      ARCH="amd64"
      ;;
    aarch64)
      ARCH="arm64"
      ;;
    *)
      log ERROR "Unsupported architecture: $ARCH. Only amd64 and arm64 are supported"
      exit 1
      ;;
  esac
  log INFO "Detected architecture: $ARCH"
}

# Detect the init system and cgroup version
detect_cgroup_config() {
   log INFO "Detecting init system and cgroup version"
    
    # Check init system
    if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
        INIT_SYSTEM="systemd"
        log INFO "Detected init system: systemd"
    else
        INIT_SYSTEM="other"
        log INFO "Detected init system: non-systemd"
    fi
    
    # Check for cgroup v2
    if [ -d /sys/fs/cgroup/cgroup.controllers ]; then
        CGROUP_VERSION="v2"
        log INFO "Detected cgroup version: v2"
    else
        CGROUP_VERSION="v1"
        log INFO "Detected cgroup version: v1"
    fi
    
    # Determine appropriate cgroup driver
    if [ "$INIT_SYSTEM" = "systemd" ] || [ "$CGROUP_VERSION" = "v2" ]; then
        CGROUP_DRIVER="systemd"
        log INFO "Using systemd cgroup driver"
    else
        CGROUP_DRIVER="cgroupfs"
        log INFO "Using cgroupfs cgroup driver"
    fi
}

# Check required ports
check_ports() {
  log INFO "Checking required ports"
  
  # Install netcat if not available
  if ! command -v nc &> /dev/null; then
    apt-get update && apt-get install -y netcat
  fi
  
  local ports_to_check=()
  
  if [ "$NODE_ROLE" = "master" ]; then
    ports_to_check=(6443 2379 2380 10250 10259 10257)
  else
    ports_to_check=(10250)
  fi
  
  for port in "${ports_to_check[@]}"; do
    if nc -z localhost "$port" &>/dev/null; then
      log WARN "Port $port is already in use. This might cause conflicts with Kubernetes"
    else
      log INFO "Port $port is available"
    fi
  done
}
