#!/usr/bin/env bash

# Installation Utility Functions
#
# This script contains utility functions for automating the installation 
# process required for setting up a Kubernetes environment. The functions include:
# - Installing necessary dependencies and tools.
# - Configuring the system environment for Kubernetes compatibility.
# - Automating repetitive setup tasks to streamline the installation process.
#
# Author: Chukwuebuka Okoli
# Email: okolisamuel21@gmail.com
# URL: https://github.com/X4MU-L

# Update system packages
update_system() {
    log INFO "Updating system packages..."
    
    apt-get update && apt-get upgrade -y
    apt-get install -y  \  
        apt-transport-https \   
        ca-certificates  \ 
        curl \ 
        gnupg \ 
        lsb-release \ 
        software-properties-common \ 
    
    log SUCCESS "System packages updated"
}


# install required dependencies
install_dependencies() {
    log INFO "install required dependencies"
    
    # Install required dependencies
    apt-get install -y  \  
        linux-modules-extra-$(uname -r)  \ 
        bpfcc-tools \
    
    # install yq
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
      chmod +x /usr/bin/yq
  
  log INFO "All dependencies are installed"
}


# Install container runtime (containerd)
install_containerd() {
    # Install containerd
    
    # Check if containerd is already installed
    if command -v containerd &> /dev/null; then
        CURRENT_VERSION=$(containerd --version | awk '{print $3}' | tr -d ',')
        if [[ "$CURRENT_VERSION" == "v${CONTAINER_RUNTIME_VERSION}" ]]; then
            log_warning "containerd ${CONTAINER_RUNTIME_VERSION} is already installed"
            return
        fi
    fi
    # Remove any existing installations of containerd
    apt-get remove -y docker docker.io containerd runc || true
    # Install containerd
    # Download the containerd tarball for the specified version
    # and extract it to /usr/local
    # The version can be passed as an argument or default to 2.0.4
    wget -q -O containerd.amd64.tar.gz https://github.com/containerd/containerd/releases/download/v${CONTAINER_RUNTIME_VERSION}/containerd-${CONTAINER_RUNTIME_VERSION}-linux-${ARCH}.tar.gz
    tar Cxzvf /usr/local containerd.amd64.tar.gz
    rm containerd.amd64.tar.gz

    # Download and install the containerd service file
    # This file is used to manage the containerd service with systemd
    # The service file is downloaded from the official containerd repository
    # and placed in the systemd directory
    sudo wget -q -O /etc/systemd/system/containerd.service \
      "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service"

    # Reload the systemd daemon to recognize the new service
    # and enable it to start on boot
    systemctl daemon-reload
    systemctl enable --now containerd
}

# Install runc
install_runc(){
    # Get the runc binary
    wget -q -O runc https://github.com/opencontainers/runc/releases/download/v1.2.6/runc.${ARCH}
    # Install runc to /usr/local/sbin
    # The runc binary is used by containerd to manage containers
    # The binary is downloaded from the official runc repository
    # and installed with the appropriate permissions
    install -m 755 runc /usr/local/sbin/runc
    # Remove the downloaded runc binary
    rm runc
}

# Download and install CNI plugins
install_cillium(){
    # Download and install CNI plugins
    # CNI plugins are used for networking in Kubernetes
    # Use Cillium as the CNI plugin
    log INFO "Installing Cilium CNI plugin"
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz{,.sha256sum}"
    sha256sum --check cilium-linux-${ARCH}.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-${ARCH}.tar.gz /usr/local/bin
    rm cilium-linux-${ARCH}.tar.gz{,.sha256sum}

    # Install Cilium CNI
    cilium install --version "$CILIUM_CLI_VERSION"

    log INFO "Cilium CNI plugin version $CILIUM_CLI_VERSION installed"
}

# Install kubeadm, kubelet, and kubectl
install_kubernetes_tools() {
  log INFO "Installing kubeadm, kubelet, and kubectl version $KUBERNETES_VERSION"

  # If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
  # sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION%.*}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION%.*}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

  # Install the Kubernetes tools (kubeadm, kubelet, kubectl)
  sudo apt-get update
  # Remove any existing versions of kubelet, kubeadm, and kubectl if any
  sudo apt-mark unhold kubelet kubeadm kubectl || true
  # Install the Kubernetes tools
  sudo apt-get install -y kubelet=${KUBERNETES_VERSION} kubeadm=${KUBERNETES_VERSION} kubectl=${KUBERNETES_VERSION}
  # Mark the Kubernetes tools to be held at the current version
  # This prevents them from being automatically updated
  sudo apt-mark hold kubelet kubeadm kubectl
  # (Optional) Enable the kubelet service before running kubeadm:
  sudo systemctl enable --now kubelet
  
  log INFO "Kubernetes tools installed"
}

# example out put
# Your Kubernetes control-plane has initialized successfully!

# To start using your cluster, you need to run the following as a regular user:

#   mkdir -p $HOME/.kube
#   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#   sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Alternatively, if you are the root user, you can run:

#   export KUBECONFIG=/etc/kubernetes/admin.conf

# You should now deploy a pod network to the cluster.
# Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
#   https://kubernetes.io/docs/concepts/cluster-administration/addons/

# You can now join any number of control-plane nodes running the following command on each as root:

#   kubeadm join 10.0.1.179:6443 --token 1m0ddi.min52hcteiok6lw6 \
# 	--discovery-token-ca-cert-hash sha256:ca478f2bb2450994a2aceb14897ac25444b4f4b5585c556be198f8915cdf9620 \
# 	--control-plane --certificate-key b2f5ee3e7bd1b28a2ed38d83f8006426268e1b4c4e9e67e8ed09057374be9014

# Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
# As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
# "kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

# Then you can join any number of worker nodes by running the following on each as root:

# kubeadm join 10.0.1.179:6443 --token 1m0ddi.min52hcteiok6lw6 \
# 	--discovery-token-ca-cert-hash sha256:ca478f2bb2450994a2aceb14897ac25444b4f4b5585c556be198f8915cdf9620 
