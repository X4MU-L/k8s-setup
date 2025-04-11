#!/usr/bin/env bash

set -euo pipefail
#
# k8s-installer: Kubernetes Cluster Setup Utility
# This script automates the installation and configuration of Kubernetes using kubeadm.
#
# Author: Chukwuebuka Okoli
# Email: okolisamuel21@gmail.com
# URL: https://github.com/X4MU-L

# Script directory
PROJECT_ROOT=$(dirname "$(readlink -f "$0")")


# Default values
KUBERNETES_VERSION="1.32.0"
CONTAINER_RUNTIME_VERSION="2.0.4"
CRI_SOCKET="/run/containerd/containerd.sock"
CNI_VERSION="1.17.2"
CNI_PROVIDER="cilium"  # Options: cilium, calico
POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_SUBNET="10.96.0.0/12"
CONTROL_PLANE_PORT="6443"
TOKEN_TTL="24h0m0s"
SKIP_CNI_INSTALL=false
FORCE_RESET=false
LOG_LEVEL="INFO"
LOG_DIR="/var/log/k8s-installer"
LOG_FILE="$LOG_DIR/k8s-installer.log"
CONTROL_PLANE_ENDPOINT=""
ARCH=""
NODE_TYPE=""
CUSTOM_TOKEN=""
JOIN_COMMAND=""
CGROUP_DRIVER=""
INIT_SYSTEM=""
CGROUP_VERSION=""
OS_DISTRO=""
OS_VERSION=""

# Source utility functions
source "$PROJECT_ROOT/utils/common.sh"
source "$PROJECT_ROOT/utils/detection.sh"
source "$PROJECT_ROOT/utils/installation.sh"
source "$PROJECT_ROOT/utils/configuration.sh"
source "$PROJECT_ROOT/utils/setup.sh"


# Main function
main() {
    log INFO "Starting Kubernetes cluster setup utility v1.0.0"
    # Check if running as root
    check_root
    # Validate parameters
    validate_params
    # Setup system environment
    setup_system_environment
    # Setup container runtime
    setup_container_runtime
    # Setup Kubernetes components
    setup_kubernetes
    # Initialize or join cluster
    if [[ "$NODE_TYPE" == "control-plane" ]]; then
        init_control_plane
        install_cni
        verify_cluster   
        # Print success message with join command
        log SUCCESS "Kubernetes control plane initialized successfully!"
        log INFO "To join worker nodes to this cluster, run the following command on each worker node:"
        log INFO "$(cat /var/log/kubeadm-join-command.txt)"
    else
        join_worker_node
        log SUCCESS "Worker node setup completed successfully!"
    fi
    log SUCCESS "Kubernetes setup completed successfully"
}

# Handle script exit
trap cleanup EXIT

# Parse command line arguments
parse_args "$@"

# Start installation
main