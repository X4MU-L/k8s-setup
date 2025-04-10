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

setup_system_environment() {
  log INFO "Setting up system environment for Kubernetes"
  
  # Create necessary directories
  create_directories
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
  

  log SUCCESS "Finshed Setting up system environment for Kubernetes"
}

setup_containerd() {
  log INFO "Setting up containerd for Kubernetes"
  
  # configure and manage system for kubernetes
  configure_system
  # Install containerd
  install_containerd
  # Install runc
  install_runc
  # install kubeneted tools
  install_kubernetes_tools

  log SUCCESS "Finished setting up containerd"
}

configure_containerd_kubeadm_and_kubelet(){
  log INFO "Configuring containerd, kubeadm, and kubelet"
  
  # Configure containerd
  configure_containerd
  # Configure kubelet
  configure_kubelet
  # Configure kubeadm
   if [ "$NODE_ROLE" = "control-plane " ]; then
      create_kubeadm_config
  fi
  
  log SUCCESS "Finished configuring containerd, kubeadm, and kubelet"
}
# Initialize Kubernetes master node
init_master_node() {
  log INFO "Initializing Kubernetes control-plane node"
  
  # Check if kubeadm has already been initialized
  if [[ -f /etc/kubernetes/admin.conf ]]; then
      log WARN "Kubernetes control plane already initialized"
  else
      # Pull container images first
      kubeadm config images pull --config /etc/kubernetes/kubeadm-config.yaml
      
      # Initialize the control-plane
      sudo kubeadm init --config=/etc/kubernetes/kubeadm-config.yaml \ 
      --upload-certs \  
      --ignore-preflight-errors=NumCPU,Mem,FileContent--proc-sys-net-ipv4-ip_forward | tee /var/log/kubeadm-init.log
  fi
  
  # Set up kubectl for root
  mkdir -p /root/.kube
  cp -f /etc/kubernetes/admin.conf /root/.kube/config
  chown $(id -u):$(id -g) /root/.kube/config
  
  # Set up kubectl for the current user if not root
  if [[ $SUDO_USER ]]; then
      USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
      mkdir -p $USER_HOME/.kube
      cp -f /etc/kubernetes/admin.conf $USER_HOME/.kube/config
      chown -R $SUDO_USER:$SUDO_USER $USER_HOME/.kube
  fi
  
  log SUCCESS "Kubernetes control plane initialized successfully"
}


# Check initialization status
check_init_status() {
    if [ "$NODE_TYPE" = "control-plane" ]; then
        log INFO "Checking control plane status..."
        # Wait for API server to become available
        timeout=60
        counter=0
        KUBECONFIG=/etc/kubernetes/admin.conf
        until kubectl get nodes &>/dev/null; do
            counter=$((counter + 1))
            if [ "$counter" -gt "$timeout" ]; then
                log ERROR "Timed out waiting for API server to become available"
                exit 1
            fi
            sleep 1
        done
        
        # Display nodes
        kubectl get nodes -o wide
    fi
    
    log SUCCESS "Node initialization completed successfully"
}
# Generate join command for worker nodes
generate_join_command() {
    log INFO "Generating join command for worker nodes..."
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    log INFO "Join command generated: ${JOIN_COMMAND}"
}

# Join worker node to the cluster
join_worker_node() {
    log INFO "Joining worker node to the cluster..."
    
    # Check if node is already part of the cluster
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        log WARN "Worker node already joined to the cluster"
        return
    fi
    
    # Execute join command
    eval $JOIN_COMMAND
    
    log SUCCESS "Worker node joined to the cluster"
}
