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
LOG_DIR="/var/log/k8s-installer"
ARCH=""
DEBUG=false
KUBERNETES_VERSION="1.32.0"
CONTAINER_RUNTIME_VERSION="2.0.4"
CILIUM_VERSION="v1.17.2"
NODE_TYPE=""
POD_NETWORK_CIDR="10.0.0.0/8"
CONTROL_PLANE_ENDPOINT=""
JOIN_COMMAND=""
CNI_PROVIDER="cilium"  # Options: cilium, calico
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


# Display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --node-type TYPE           Specify node type (control-plane or worker)"
    echo "  --k8s-version VERSION      Kubernetes version to install (default: ${KUBERNETES_VERSION})"
    echo "  --container-runtime-version VERSION  Container runtime version (default: ${CONTAINER_RUNTIME_VERSION})"
    echo "  --cilium-version VERSION   Cilium CNI version (default: ${CILIUM_VERSION})"
    echo "  --cni-provider PROVIDER    CNI provider (cilium or calico, default: ${CNI_PROVIDER})"
    echo "  --pod-network-cidr CIDR    Pod network CIDR (default: ${POD_NETWORK_CIDR})"
    echo "  --control-plane-endpoint ENDPOINT  Control plane endpoint (required for control-plane)"
    echo "  --join-command COMMAND     Join command (required for worker nodes)"
    echo "  --help                     Display this help message"
    echo ""
    echo "Example:"
    echo "  Control plane: $0 --node-type control-plane --control-plane-endpoint k8s-master.example.com"
    echo "  Worker node:   $0 --node-type worker --join-command 'kubeadm join ...'"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-type)
                NODE_TYPE="$2"
                shift 2
                ;;
            --k8s-version)
                KUBERNETES_VERSION="$2"
                shift 2
                ;;
            --container-runtime-version)
                CONTAINER_RUNTIME_VERSION="$2"
                shift 2
                ;;
            --cilium-version)
                CILIUM_VERSION="$2"
                shift 2
                ;;
            --pod-network-cidr)
                POD_NETWORK_CIDR="$2"
                shift 2
                ;;
            --control-plane-endpoint)
                CONTROL_PLANE_ENDPOINT="$2"
                shift 2
                ;;
            --join-command)
                JOIN_COMMAND="$2"
                shift 2
                ;;
            -v|-vv|-vvv|--debug|--verbose)
                DEBUG=true
                shift 2
                ;;  
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

     # Validate required parameters
    if [[ -z "$NODE_TYPE" ]]; then
        log ERROR "Node type is required. Use --node-type control-plane or --node-type worker"
        usage
        exit 1
    fi

    if [[ "$NODE_TYPE" != "control-plane" && "$NODE_TYPE" != "worker" ]]; then
        log ERROR "Invalid node type. Use --node-type control-plane or --node-type worker"
        usage
        exit 1
    fi

    if [[ "$NODE_TYPE" == "control-plane" && -z "$CONTROL_PLANE_ENDPOINT" ]]; then
        log ERROR "Control plane endpoint is required for control plane nodes"
        usage
        exit 1
    fi

    if [[ "$NODE_TYPE" == "worker" && -z "$JOIN_COMMAND" ]]; then
        log ERROR "Join command is required for worker nodes"
        usage
        exit 1
    fi

   log INFO "Parsed arguments: NODE_TYPE=$NODE_TYPE, KUBERNETES_VERSION=$KUBERNETES_VERSION, CILIUM_VERSION=$CILIUM_VERSION, POD_NETWORK_CIDR=$POD_NETWORK_CIDR, CONTROL_PLANE_ENDPOINT=$CONTROL_PLANE_ENDPOINT, JOIN_COMMAND=$JOIN_COMMAND"
}

# Main function
main() {
  log INFO "Starting Kubernetes installation with version $KUBERNETES_VERSION, role: $NODE_TYPE"
  
  check_root
  setup_system_environment
  setup_containerd
  configure_containerd_kubeadm_and_kubelet
  
  if [ "$NODE_TYPE" = "control-plane " ]; then
    init_master_node
  else
    join_worker_node
  fi
  check_init_status
  
  log SUCCESS "Kubernetes setup completed successfully"
}

# Handle script exit
trap cleanup EXIT

# Start installation
parse_args "$@"
main
