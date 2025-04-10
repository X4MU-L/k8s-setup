#!/usr/bin/env bash

# Configuration utility functions
# 
# This script contains utility functions for configuring a Kubernetes setup.
# The functions include:
# - Disabling swap to meet Kubernetes requirements.
# - Configuring system settings such as loading necessary modules and setting sysctl parameters.
# - Configuring kubelet to use the appropriate cgroup driver.
# - Creating kubeadm configuration files for initializing the control plane.
# - Generating the join command for worker nodes.
#
# Author: Chukwuebuka Okoli
# Email: okolisamuel21@gmail.com
# URL: https://github.com/X4MU-L

# Disable swap
disable_swap() {
    log INFO "Disabling swap"
    # Check if swap is enabled
    if grep -q "swap" /etc/fstab; then
        log INFO "Swap found in /etc/fstab, disabling..."
        # Comment out swap lines in fstab
        sed -i '/swap/s/^/#/' /etc/fstab
        log INFO "Swap disabled in /etc/fstab"
    else
        log INFO "No swap found in /etc/fstab"
    fi
    # Turn off swap
    swapoff -a || log WARN "Failed to turn off swap, continuing anyway"
    log SUCCESS "Swap disabled"
}

# Configure system settings
configure_system() {
    log INFO "Configuring system settings for Kubernetes"

    # Create necessary configuration directories
    mkdir -p /etc/modules-load.d
    mkdir -p /etc/sysctl.d

    # Configure kernel modules
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
ip_tables
nf_nat
nf_conntrack
EOF

    # Load necessary modules
    modprobe overlay || log WARN "Failed to load overlay module"
    modprobe br_netfilter || log WARN "Failed to load br_netfilter module"
    modprobe ip_tables || log WARN "Failed to load ip_tables module"
    modprobe nf_nat || log WARN "Failed to load nf_nat module"
    modprobe nf_conntrack || modprobe nf_conntrack_ipv4 || log WARN "Failed to load nf_conntrack module"

    # Set sysctl parameters
    tee /etc/sysctl.d/k8s.conf > /dev/null << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF

    # Apply sysctl parameters
    sysctl --system > /dev/null 2>&1 || log WARN "Failed to apply sysctl parameters"

    log SUCCESS "System configured for Kubernetes"
}

# Configure containerd
configure_containerd() {
    log INFO "Configuring containerd"
    # Create the configuration directory
    mkdir -p /etc/containerd
    # Generate default config
    containerd config default | tee /etc/containerd/config.toml > /dev/null || {
        log ERROR "Failed to generate containerd config"
        exit 1
    }
    # Update SystemdCgroup setting
    if grep -q "SystemdCgroup" /etc/containerd/config.toml; then
        sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml || {
            log WARN "Failed to update SystemdCgroup setting"
        }
    else
        # Add it if it doesn't exist
        sed -i 's/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options\]/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options\]\n    SystemdCgroup = true/' /etc/containerd/config.toml || {
            log WARN "Failed to add SystemdCgroup setting"
        }
    fi
    # Create crictl configuration
    mkdir -p /etc
    cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix://${CRI_SOCKET}
image-endpoint: unix://${CRI_SOCKET}
timeout: 10
debug: false
EOF
    
    # Restart containerd
    systemctl restart containerd || {
        log ERROR "Failed to restart containerd"
        exit 1
    }
    
    # Verify containerd is running
    if ! systemctl is-active --quiet containerd; then
        log ERROR "containerd service is not running"
        exit 1
    fi
    log SUCCESS "containerd configured successfully"
}

# Create kubeadm configuration
create_kubeadm_config() {
    log INFO "Creating kubeadm configuration"
    
    # Create kubernetes directory
    mkdir -p /etc/kubernetes
    
    # Determine the full control plane endpoint
    local full_endpoint="${CONTROL_PLANE_ENDPOINT}:${CONTROL_PLANE_PORT}"
    
    # Create bootstrap token configuration
    local token_config=""
    if [[ -n "$CUSTOM_TOKEN" ]]; then
        token_config="  token: $CUSTOM_TOKEN"
    fi
    
    # Create kubeadm configuration file
    tee  /etc/kubernetes/kubeadm-config.yaml > /dev/null  << EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
${token_config}
  ttl: ${TOKEN_TTL}
  usages:
  - signing
  - authentication
nodeRegistration:
  criSocket: unix://${CRI_SOCKET}
  name: $(hostname -s)
  kubeletExtraArgs:
    cgroup-driver: ${CGROUP_DRIVER}
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v${KUBERNETES_VERSION}
controlPlaneEndpoint: "${full_endpoint}"
networking:
  podSubnet: "${POD_NETWORK_CIDR}"
  serviceSubnet: "${SERVICE_SUBNET}"
  dnsDomain: "cluster.local"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "${CGROUP_DRIVER}"
EOF
    
    log SUCCESS "kubeadm configuration created successfully"
}

# Configure kubelet
configure_kubelet() {
    log INFO "Configuring kubelet to use $CGROUP_DRIVER cgroup driver"
    # Create kubelet configuration directory
    mkdir -p /etc/systemd/system/kubelet.service.d/
    # Create kubelet service configuration
    tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf > /dev/null << EOF
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix://${CRI_SOCKET} --cgroup-driver=${CGROUP_DRIVER}"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF
    
    # Create kubelet defaults file
    tee /etc/default/kubelet  > /dev/null << EOF
KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix://${CRI_SOCKET} --cgroup-driver=${CGROUP_DRIVER}"
EOF
    # Reload systemd and restart kubelet
    systemctl daemon-reload || {
        log ERROR "Failed to reload systemd daemon"
        exit 1
    }
    # Restart kubelet (may fail if not initialized yet, which is normal)
    systemctl restart kubelet || log DEBUG "Kubelet restart failed, this is normal before kubeadm init/join"
    log SUCCESS "Kubelet configured successfully"
}

# Generate join command
generate_join_command() {
  log INFO "Generating worker node join command"
  
  JOIN_COMMAND=$(kubeadm token create --print-join-command)
  log INFO "Join command: $JOIN_COMMAND"
  echo "$JOIN_COMMAND" > /etc/kubernetes/join-command.sh
  chmod +x /etc/kubernetes/join-command.sh
  
  log INFO "Join command saved to /etc/kubernetes/join-command.sh"
}