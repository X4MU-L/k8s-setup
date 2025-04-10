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
    
    apt-get update > /dev/null 2>&1 || { log ERROR "Failed to update package lists"; exit 1; }
    apt-get upgrade -y > /dev/null 2>&1 || { log WARN "Failed to upgrade packages, continuing anyway"; }

    log SUCCESS "System packages updated"
    
    log INFO "Installing required system packages"
    apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release \
        iptables software-properties-common > /dev/null 2>&1 || { 
            log ERROR "Failed to install required packages"; 
            exit 1; 
        }
    
    log SUCCESS "Required system packages installed"
}

# Install required dependencies
install_dependencies() {
    log INFO "Installing required dependencies"
    
    apt-get install -y linux-modules-extra-$(uname -r) bpfcc-tools > /dev/null 2>&1 || {
        log WARN "Failed to install some kernel modules, continuing anyway"
    }
    
    # Install yq for YAML processing
    # if ! command -v yq &> /dev/null; then
    #     log INFO "Installing yq for YAML processing"
    #     wget -q -O /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    #         chmod +x /usr/bin/yq || {
    #             log WARN "Failed to install yq, continuing without it"
    #         }
    # fi
    log SUCCESS "All dependencies installed"
}

# Install runc
install_runc() {
    log INFO "Installing runc"
    # Check if runc is already installed
    if command -v runc &> /dev/null; then
        CURRENT_VERSION=$(runc --version | head -n 1 | awk '{print $3}')
        log INFO "runc version $CURRENT_VERSION is already installed"
        return
    fi
    # Install runc
    
    wget -q -O runc.amd64 https://github.com/opencontainers/runc/releases/download/v1.2.6/runc.${ARCH} || {
        log ERROR "Failed to download runc"
        exit 1
    }
    install -m 755 runc.amd64 /usr/local/sbin/runc > /dev/null 2>&1
    rm runc.amd64
    log SUCCESS "runc installed successfully"
}

# Install containerd
install_containerd() {
    log INFO "Installing containerd version ${CONTAINER_RUNTIME_VERSION}"
    # Check if containerd is already installed
    if command -v containerd &> /dev/null; then
        CURRENT_VERSION=$(containerd --version | awk '{print $3}' | tr -d ',')
        if [[ "$CURRENT_VERSION" == "v${CONTAINER_RUNTIME_VERSION}" ]]; then
            log INFO "containerd ${CONTAINER_RUNTIME_VERSION} is already installed"
            return
        fi
        log INFO "Upgrading containerd from $CURRENT_VERSION to v${CONTAINER_RUNTIME_VERSION}"
    fi
    # Remove any existing installations of containerd
    apt-get remove -y docker docker.io containerd runc > /dev/null 2>&1 || true
    # Download and install containerd
    wget -q -O containerd.tar.gz "https://github.com/containerd/containerd/releases/download/v${CONTAINER_RUNTIME_VERSION}/containerd-${CONTAINER_RUNTIME_VERSION}-linux-${ARCH}.tar.gz" || {
        log ERROR "Failed to download containerd"
        exit 1
    }
    tar Cxzf /usr/local containerd.tar.gz > /dev/null 2>&1 || {
        log ERROR "Failed to extract containerd"
        exit 1
    }
    rm containerd.tar.gz
    # Download and install the containerd service file
    wget -q -O /etc/systemd/system/containerd.service \
        "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service" || {
        log ERROR "Failed to download containerd service file"
        exit 1
    }
    # Reload systemd and enable containerd
    systemctl daemon-reload
    systemctl enable --now containerd > /dev/null 2>&1 || {
        log ERROR "Failed to enable containerd service"
        exit 1
    }
    log SUCCESS "Containerd version ${CONTAINER_RUNTIME_VERSION} installed and service started"
}

# Install Kubernetes tools (kubeadm, kubelet, kubectl)
install_kubernetes_tools() {
    log INFO "Installing kubeadm, kubelet, and kubectl version $KUBERNETES_VERSION"
    # Create keyrings directory if it doesn't exist
    mkdir -p -m 755 /etc/apt/keyrings
    # Add Kubernetes apt repository
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION%.*}/deb/Release.key" | gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || {
        log ERROR "Failed to add Kubernetes apt key"
        exit 1
    }
    # Add Kubernetes apt repository
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION%.*}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list || {
        log ERROR "Failed to add Kubernetes apt repository"
        exit 1
    }
    # Update apt and install Kubernetes tools
    apt-get update > /dev/null 2>&1 || {
        log ERROR "Failed to update apt after adding Kubernetes repository"
        exit 1
    }
    # Remove any holds on Kubernetes packages
    apt-mark unhold kubelet kubeadm kubectl > /dev/null 2>&1 || true
    # Install specific versions of Kubernetes tools
    apt-get install -y kubelet=${KUBERNETES_VERSION}-* kubeadm=${KUBERNETES_VERSION}-* kubectl=${KUBERNETES_VERSION}-* || {
        log ERROR "Failed to install Kubernetes tools"
        exit 1
    }
    # Hold Kubernetes packages to prevent automatic updates
    apt-mark hold kubelet kubeadm kubectl || {
        log WARN "Failed to hold Kubernetes packages"
    }
    # Enable kubelet service
    systemctl enable kubelet || {
        log WARN "Failed to enable kubelet service"
    }
    log SUCCESS "Kubernetes tools installed successfully"
}

# Install CNI plugin
install_cni() {
    if [[ "$SKIP_CNI_INSTALL" == "true" ]]; then
        log INFO "Skipping CNI installation as requested"
        return
    fi
    log INFO "Installing CNI plugin: $CNI_PROVIDER"
    case $CNI_PROVIDER in
        cilium)
            install_cilium
            ;;
        calico)
            install_calico
            ;;
        flannel)
            install_flannel
            ;;
        *)
            log ERROR "Unsupported CNI plugin: $CNI_PROVIDER"
            exit 1
            ;;
    esac
}

# Install Cilium CNI
install_cilium() {
    log INFO "Installing Cilium CNI"
    # Install Cilium CLI
    if ! command -v cilium &> /dev/null; then
        log INFO "Installing Cilium CLI"
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        CLI_ARCH=amd64
        if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}  > /dev/null 2>&1 || {
            log ERROR "Failed to download Cilium CLI"
            exit 1
        }
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
        tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin > /dev/null 2>&1
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

    fi
    # Install Cilium
    cilium install --version $CNI_VERSION || {
        log ERROR "Failed to install Cilium"
        exit 1
    }
    # Wait for Cilium to be ready
    cilium status --wait || log WARN "Cilium is not fully ready yet"
    log SUCCESS "Cilium CNI installed successfully"
}

# Install Calico CNI
install_calico() {
    log INFO "Installing Calico CNI"
    # Download Calico manifest
    curl -L https://raw.githubusercontent.com/projectcalico/calico/v${CNI_VERSION}/manifests/calico.yaml -o calico.yaml || {
        log ERROR "Failed to download Calico manifest"
        exit 1
    }
    # Update pod CIDR if needed
    if [[ "$POD_NETWORK_CIDR" != "192.168.0.0/16" ]]; then
        log INFO "Updating Calico manifest with custom pod CIDR: $POD_NETWORK_CIDR"
        sed -i "s|192.168.0.0/16|$POD_NETWORK_CIDR|g" calico.yaml
    fi  
    # Apply Calico manifest
    kubectl apply -f calico.yaml || {
        log ERROR "Failed to apply Calico manifest"
        rm calico.yaml
        exit 1
    }
    rm calico.yaml
    # Wait for Calico pods to be ready
    log INFO "Waiting for Calico pods to be ready..."
    kubectl -n kube-system wait --for=condition=ready pod -l k8s-app=calico-node --timeout=300s || log WARN "Calico pods are not fully ready yet"
    log SUCCESS "Calico CNI installed successfully"
}

# Install Flannel CNI
install_flannel() {
    log INFO "Installing Flannel CNI"
    # Download Flannel manifest
    curl -L https://raw.githubusercontent.com/flannel-io/flannel/v${CNI_VERSION}/Documentation/kube-flannel.yml -o kube-flannel.yml || {
        log ERROR "Failed to download Flannel manifest"
        exit 1
    } 
    # Update pod CIDR if needed
    if [[ "$POD_NETWORK_CIDR" != "10.244.0.0/16" ]]; then
        log INFO "Updating Flannel manifest with custom pod CIDR: $POD_NETWORK_CIDR"
        sed -i "s|10.244.0.0/16|$POD_NETWORK_CIDR|g" kube-flannel.yml
    fi
    # Apply Flannel manifest
    kubectl apply -f kube-flannel.yml || {
        log ERROR "Failed to apply Flannel manifest"
        rm kube-flannel.yml
        exit 1
    }
    
    rm kube-flannel.yml
    # Wait for Flannel pods to be ready
    log INFO "Waiting for Flannel pods to be ready..."
    kubectl -n kube-system wait --for=condition=ready pod -l app=flannel --timeout=300s || log WARN "Flannel pods are not fully ready yet"
    log SUCCESS "Flannel CNI installed successfully"
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


# Install runc
install_runc(){
    log INFO "Installing runc"
    # Get the runc binary
    wget -q -O runc https://github.com/opencontainers/runc/releases/download/v1.2.6/runc.${ARCH} > /dev/null 2>&1
    # Install runc to /usr/local/sbin
    # The runc binary is used by containerd to manage containers
    # The binary is downloaded from the official runc repository
    # and installed with the appropriate permissions
    install -m 755 runc /usr/local/sbin/runc > /dev/null 2>&1
    # Remove the downloaded runc binary
    rm runc

    log SUCCESS "runc installed"
}
