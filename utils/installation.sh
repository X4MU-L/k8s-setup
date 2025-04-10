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
    
    apt-get update > /dev/null 2>&1
    apt-get upgrade -y  > /dev/null 2>&1

    log SUCCESS "System packages updated"
    log INFO "Installing required system packages"
    # Install required system packages
    apt-get install -y  curl wget apt-transport-https ca-certificates gnupg lsb-release iptables software-properties-common > /dev/null 2>&1
    
    log SUCCESS "Installing required system packages compelted"
}


# install required dependencies
install_dependencies() {
    log INFO "install required dependencies"
    
    # Install required dependencies
    apt-get install -y  linux-modules-extra-$(uname -r) bpfcc-tools  > /dev/null 2>&1
    
    # install yq
    wget -q -O /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64  && \
      chmod +x /usr/bin/yq > /dev/null 2>&1
  
  log INFO "All dependencies are installed"
}


# Install container runtime (containerd)
install_containerd() {
    # Install containerd
    log INFO "Installing containerd version ${CONTAINER_RUNTIME_VERSION}"
    # Check if containerd is already installed
    if command -v containerd &> /dev/null; then
        CURRENT_VERSION=$(containerd --version | awk '{print $3}' | tr -d ',')
        if [[ "$CURRENT_VERSION" == "v${CONTAINER_RUNTIME_VERSION}" ]]; then
            log WARN "containerd ${CONTAINER_RUNTIME_VERSION} is already installed"
            return
        fi
    fi
    # Remove any existing installations of containerd
    apt-get remove -y docker docker.io containerd runc || true
    # Install containerd
    # Download the containerd tarball for the specified version
    # and extract it to /usr/local
    # The version can be passed as an argument or default to 2.0.4
    wget -q -O containerd.amd64.tar.gz https://github.com/containerd/containerd/releases/download/v${CONTAINER_RUNTIME_VERSION}/containerd-${CONTAINER_RUNTIME_VERSION}-linux-${ARCH}.tar.gz > /dev/null 2>&1
    tar Cxzvf /usr/local containerd.amd64.tar.gz > /dev/null 2>&1
    rm containerd.amd64.tar.gz

    # Download and install the containerd service file
    # This file is used to manage the containerd service with systemd
    # The service file is downloaded from the official containerd repository
    # and placed in the systemd directory
    sudo wget -q -O /etc/systemd/system/containerd.service \
      "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service" > /dev/null 2>&1

    # Reload the systemd daemon to recognize the new service
    # and enable it to start on boot
    systemctl daemon-reload
    systemctl enable --now containerd

    log SUCCESS "Containerd version ${CONTAINER_RUNTIME_VERSION} installed and service started"
}

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

# Download and install CNI plugins
install_cillium(){
    # Download and install CNI plugins
    # CNI plugins are used for networking in Kubernetes
    # Use Cillium as the CNI plugin
    log INFO "Installing Cilium CNI plugin"
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz{,.sha256sum}" > /dev/null 2>&1
    sha256sum --check cilium-linux-${ARCH}.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-${ARCH}.tar.gz /usr/local/bin > /dev/null 2>&1
    rm cilium-linux-${ARCH}.tar.gz{,.sha256sum}

    # Install Cilium CNI
    cilium install --version "$CILIUM_CLI_VERSION"

    log INFO "Cilium CNI plugin version $CILIUM_CLI_VERSION installed"
}

# Install chosen CNI plugin
install_cni() {
  log INFO "Installing CNI plugin: $CNI_PROVIDER"
  
  case $CNI_PROVIDER in
    cilium)
      install_cillium
      ;;
    calico)
      install_calico
      ;;
    *)
      log ERROR "Unsupported CNI plugin: $CNI_PROVIDER"
      exit 1
      ;;
  esac
}

# Install Calico CNI
install_calico() {
  log INFO "Installing Calico CNI"
  
  # Adjust for Calico's expected CIDR if necessary
    if [ "$POD_NETWORK_CIDR" != "192.168.0.0/16" ]; then
        log WARN "Calico default CIDR is 192.168.0.0/16, but you specified $POD_NETWORK_CIDR"
        log WARN "This may require additional configuration"
    fi
  
    # Install Calico
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
  
    # Create Calico custom resource with specified CIDR
    cat > /tmp/calico-cr.yaml << EOF
    apiVersion: operator.tigera.io/v1
    kind: Installation
    metadata:
    name: default
    spec:
    calicoNetwork:
        ipPools:
        - blockSize: 26
        cidr: ${POD_NETWORK_CIDR}
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
EOF

    kubectl create -f /tmp/calico-cr.yaml
    rm /tmp/calico-cr.yaml
  
    log INFO "Calico installed successfully"
}


# Install kubeadm, kubelet, and kubectl
install_kubernetes_tools() {
  log INFO "Installing kubeadm, kubelet, and kubectl version $KUBERNETES_VERSION"

  # If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
  # sudo mkdir -p -m 755 /etc/apt/keyrings
  log INFO "Adding Kubernetes APT repository"
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION%.*}/deb/Release.key  | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg  > /dev/null 2>&1

  # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION%.*}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

  log INFO "Adding Kubernetes APT repository completed"
  # Install the Kubernetes tools (kubeadm, kubelet, kubectl)
  sudo apt-get update > /dev/null 2>&1
  # Remove any existing versions of kubelet, kubeadm, and kubectl if any
  sudo apt-mark unhold kubelet kubeadm kubectl || true > /dev/null 2>&1
  # Install the Kubernetes tools
  sudo apt-get install -y kubelet=${KUBERNETES_VERSION}-1.1 kubeadm=${KUBERNETES_VERSION}-1.1 kubectl=${KUBERNETES_VERSION}-1.1 > /dev/null 2>&1
  # Mark the Kubernetes tools to be held at the current version
  # This prevents them from being automatically updated
  sudo apt-mark hold kubelet kubeadm kubectl > /dev/null 2>&1
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
