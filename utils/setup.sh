#!/usr/bin/env bash

# Kubernetes Cluster Setup Functions
#
# This script provides utility functions to facilitate the setup of a Kubernetes cluster.
# It includes essential operations required for initializing and configuring the cluster
# environment. The functions may include:
# - Installing necessary dependencies and tools for Kubernetes.
# - Configuring cluster networking and storage.
# - Setting up control plane and worker nodes.
# - Validating the cluster setup for readiness.
#
# Author: Chukwuebuka Okoli
# Email: okolisamuel21@gmail.com
# URL: https://github.com/X4MU-L
# Kubernetes cluster setup functions

# Setup system environment
setup_system_environment() {
    log INFO "Setting up system environment for Kubernetes"
    # Update system packages
    update_system
    # Install needed dependencies
    install_dependencies
    # Detect OS and architecture
    detect_os_and_arch
    # Detect cgroup configuration
    detect_cgroup_config
    # Disable swap
    disable_swap
    # Configure system settings
    configure_system
    log SUCCESS "System environment setup completed"
}

# Setup container runtime
setup_container_runtime() {
    log INFO "Setting up container runtime"
    # Install runc
    install_runc
    # Install containerd
    install_containerd
    # Configure containerd
    configure_containerd
    log SUCCESS "Container runtime setup completed"
}

# Setup Kubernetes components
setup_kubernetes() {
    log INFO "Setting up Kubernetes components"
    # Install Kubernetes tools
    install_kubernetes_tools
    # Configure kubelet
    configure_kubelet
    log SUCCESS "Kubernetes components setup completed"
}
# Initialize control plane node
init_control_plane() {
    log INFO "Initializing Kubernetes control plane node"
    # Check if kubeadm has already been initialized
    if [[ -f /etc/kubernetes/admin.conf ]]; then
        if [[ "$FORCE_RESET" == "true" ]]; then
            log WARN "Existing Kubernetes control plane found, resetting due to --force-reset flag"
            kubeadm reset -f || {
                log ERROR "Failed to reset existing Kubernetes cluster"
                exit 1
            }
        else
            log WARN "Kubernetes control plane already initialized, skipping initialization"
            return
        fi
    fi
    # Create kubeadm configuration
    create_kubeadm_config
    # Pull container images first
    log INFO "Pulling container images for Kubernetes control plane"
    kubeadm config images pull --config /etc/kubernetes/kubeadm-config.yaml > /dev/null 2>&1 || {
        log WARN "Failed to pull some container images, continuing anyway"
    }
    # Initialize the control plane
    log INFO "Running kubeadm init to initialize the control plane"
    kubeadm init --config=/etc/kubernetes/kubeadm-config.yaml --upload-certs --ignore-preflight-errors=NumCPU,Mem | tee /var/log/kubeadm-init.log > /dev/null 2>&1 || {
        log ERROR "Failed to initialize Kubernetes control plane"
        exit 1
    } 
    # Set up kubectl for the root user
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    # Set up kubectl for the sudo user if applicable
    if [[ -n "$SUDO_USER" ]]; then
        USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
        mkdir -p $USER_HOME/.kube
        cp -f /etc/kubernetes/admin.conf $USER_HOME/.kube/config
        chown -R $SUDO_USER:$SUDO_USER $USER_HOME/.kube
        log INFO "kubectl configured for user $SUDO_USER"
    fi
    # Extract join command for worker nodes
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    echo "$JOIN_COMMAND" | tee /var/log/kubeadm-join-command.txt > /dev/null
    log INFO "Join command saved to /var/log/kubeadm-join-command.txt"
    log SUCCESS "Kubernetes control plane initialized successfully"
}

# Join worker node to the cluster
join_worker_node() {
    log INFO "Joining worker node to the Kubernetes cluster"
    # Check if node is already part of a cluster
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        if [[ "$FORCE_RESET" == "true" ]]; then
            log WARN "Node is already part of a cluster, resetting due to --force-reset flag"
            kubeadm reset -f || {
                log ERROR "Failed to reset existing Kubernetes configuration"
                exit 1
            }
        else
            log WARN "Node is already part of a cluster, skipping join"
            return
        fi
    fi
    # Construct join command
    local join_command=""
    if [[ -n "$CUSTOM_TOKEN" ]]; then
        # Use provided token
        join_command="kubeadm join ${CONTROL_PLANE_ENDPOINT}:${CONTROL_PLANE_PORT} --token ${CUSTOM_TOKEN} --discovery-token-unsafe-skip-ca-verification"
    else
        # Prompt for join command
        log INFO "No token provided. Please enter the join command from the control plane node:"
        log INFO "You can get this by running 'kubeadm token create --print-join-command' on the control plane node"
        read -p "Join command: " join_command
        if [[ -z "$join_command" ]]; then
            log ERROR "No join command provided"
            exit 1
        fi
    fi
    
    # Add cri-socket flag if not present
    if [[ ! "$join_command" =~ "--cri-socket" ]]; then
        join_command="$join_command --cri-socket=unix://${CRI_SOCKET}"
    fi
    
    # Execute join command
    log INFO "Executing join command"
    eval $join_command || {
        log ERROR "Failed to join the cluster"
        exit 1
    }
    log SUCCESS "Worker node joined the cluster successfully"
}