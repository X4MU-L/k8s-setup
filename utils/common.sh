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
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Only log if the level is at or above the configured log level
    case $LOG_LEVEL in
        DEBUG)
            ;;
        INFO)
            if [ "$level" = "DEBUG" ]; then return; fi
            ;;
        WARN)
            if [ "$level" = "DEBUG" ] || [ "$level" = "INFO" ]; then return; fi
            ;;
        ERROR)
            if [ "$level" = "DEBUG" ] || [ "$level" = "INFO" ] || [ "$level" = "WARN" ]; then return; fi
            ;;
    esac
    
    case $level in
        DEBUG)
            echo -e "${PURPLE}[DEBUG]${NC} $timestamp - $message"
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $timestamp - $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $timestamp - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $timestamp - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message"
            ;;
        *)
            echo -e "$timestamp - $message"
            ;;
    esac
    
    # Also log to file if LOG_FILE is set
    if [ -n "$LOG_FILE" ]; then
        echo "[$level] $timestamp - $message" >> "$LOG_FILE"
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

# Display help message
show_help() {
    cat << EOF
Kubernetes Cluster Setup Script

Usage: $0 [options]

Options:
  \t-t, --node-type <type>              Node type: 'control-plane' or 'worker'
  \t-k, --kubernetes-version <version>  Kubernetes version to install (default: 1.32.0)
  \t-r, --container-runtime-version <v> Container runtime version (default: 2.0.4)
  \t-c, --cni <provider>                CNI provider: 'cilium', 'calico', 'flannel' (default: cilium)
  \t-C, --cni-version <version>         CNI version (default: 1.17.2)
  \t-p, --pod-cidr <cidr>               Pod network CIDR (default: 10.244.0.0/16)
  \t-s, --service-cidr <cidr>           Service network CIDR (default: 10.96.0.0/12)
  \t-e, --control-plane-endpoint <ep>   Control plane endpoint (required for control-plane)
  \t--control-plane-port <port>         Control plane port (default: 6443)
  \t--token <token>                     Bootstrap token (optional, auto-generated if not provided)
  \t--token-ttl <duration>              Token time-to-live (default: 24h0m0s)
  \t--skip-cni                          Skip CNI installation
  \t--force-reset                       Force reset existing Kubernetes setup
  \t--log-level <level>                 Log level: DEBUG, INFO, WARN, ERROR (default: INFO)
  \t-v, -vv, -vvv, --debug, --verbose   Enable verbose logging (takes precedence over --log-level)
  \t--log-file <file>                   Log to file in addition to stdout (default: $LOG_FILE)
  \t-h, --help                          Show this help message

Examples:
  \t# Setup a control plane node
  \t$0 --node-type control-plane --control-plane-endpoint k8s-master.example.com

  \t# Setup a worker node
  \t$0 --node-type worker --control-plane-endpoint k8s-master.example.com join-command 'kubeadm join ...
EOF
}
# Validate required parameters
validate_params() {
    log INFO "Validating parameters..."
    
    # Validate node type
    if [[ "$NODE_TYPE" != "control-plane" && "$NODE_TYPE" != "worker" ]]; then
        log ERROR "Invalid node type: $NODE_TYPE. Must be 'control-plane' or 'worker'"
        exit 1
    fi
    
    # Validate control plane endpoint for control-plane nodes
    if [[ "$NODE_TYPE" == "control-plane" && -z "$CONTROL_PLANE_ENDPOINT" ]]; then
        # If not provided, use the hostname
        HOSTNAME=$(hostname -f)
        log WARN "Control plane endpoint not provided. Using hostname: $HOSTNAME"
        CONTROL_PLANE_ENDPOINT="$HOSTNAME"
    fi
    
    # Validate control plane endpoint for worker nodes
    if [[ "$NODE_TYPE" == "worker" && -z "$CONTROL_PLANE_ENDPOINT" ]]; then
        log ERROR "Control plane endpoint is required for worker nodes"
        exit 1
    fi
    
    if [[ "$NODE_TYPE" == "worker" && -z "$JOIN_COMMAND" ]]; then
        log ERROR "Join command is required for worker nodes"
        exit 1
    fi

    # Validate CNI provider
    case $CNI_PROVIDER in
        cilium|calico|flannel)
            log INFO "Using CNI provider: $CNI_PROVIDER"
            ;;
        *)
            log ERROR "Unsupported CNI provider: $CNI_PROVIDER. Must be 'cilium', 'calico', or 'flannel'"
            exit 1
            ;;
    esac
    
    # Set pod CIDR based on CNI if not explicitly provided
    if [[ "$POD_NETWORK_CIDR" == "10.244.0.0/16" ]]; then
        case $CNI_PROVIDER in
            cilium)
                POD_NETWORK_CIDR="10.217.0.0/16"
                ;;
            calico)
                POD_NETWORK_CIDR="192.168.0.0/16"
                ;;
            flannel)
                POD_NETWORK_CIDR="10.244.0.0/16"
                ;;
        esac
        log INFO "Using default pod CIDR for $CNI_PROVIDER: $POD_NETWORK_CIDR"
    fi
    
    log SUCCESS "Parameters validated successfully"
}


# Perform cleanup on script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Script execution failed with exit code $exit_code"
    else
        log SUCCESS "Script execution completed successfully"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--node-type)
                NODE_TYPE="$2"
                shift 2
                ;;
            -k|--kubernetes-version)
                KUBERNETES_VERSION="$2"
                shift 2
                ;;
            -r|--container-runtime-version)
                CONTAINER_RUNTIME_VERSION="$2"
                shift 2
                ;;
            -c|--cni)
                CNI_PROVIDER="$2"
                shift 2
                ;;
            -C|--cni-version)
                CNI_VERSION="$2"
                shift 2
                ;;
            -p|--pod-cidr)
                POD_NETWORK_CIDR="$2"
                shift 2
                ;;
            -s|--service-cidr)
                SERVICE_SUBNET="$2"
                shift 2
                ;;
            -e|--control-plane-endpoint)
                CONTROL_PLANE_ENDPOINT="$2"
                shift 2
                ;;
            --control-plane-port)
                CONTROL_PLANE_PORT="$2"
                shift 2
                ;;
            --token)
                CUSTOM_TOKEN="$2"
                shift 2
                ;;
            --token-ttl)
                TOKEN_TTL="$2"
                shift 2
                ;;
            --skip-cni)
                SKIP_CNI_INSTALL=true
                shift
                ;;
            --force-reset)
                FORCE_RESET=true
                shift
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -v|-vv|-vvv|--debug|--verbose)
                LOG_LEVEL="DEBUG"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

log INFO "Parsed arguments: \n using -> \tNODE TYPE=$NODE_TYPE,\n \t\tKUBERNETES VERSION=$KUBERNETES_VERSION,\n \t\tCNI PROVIDER=$CNI_PROVIDER,\n \t\tCNI VERSION=$CNI_VERSION,\n \t\tPOD NETWORK CIDR=$POD_NETWORK_CIDR,\n \t\tSERVICE SUBNET=$SERVICE_SUBNET,\n \t\tCONTROL PLANE ENDPOINT=$CONTROL_PLANE_ENDPOINT,\n \t\tJOIN COMMAND=$JOIN_COMMAND"
}
