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
  
  # Disable swap
  swapoff -a
  
  # Comment out swap entries in /etc/fstab
  sed -i '/ swap / s/^/#/' /etc/fstab
  
  log INFO "Swap disabled"
}

# Configure system settings
configure_system() {
  log INFO "Configuring system settings"

  # Create necessary configuration directories
  mkdir -p /etc/modules-load.d
  mkdir -p /etc/sysctl.d

  # Configure kernel modules
    tee /etc/modules-load.d/k8s.conf > /dev/null  << EOF
    overlay
    br_netfilter
    ip_tables
    nf_nat
    nf_conntrack
EOF

    # Load necessary modules
    modprobe overlay
    modprobe br_netfilter
    modprobe ip_tables
    modprobe nf_nat
    modprobe nf_conntrack || true # Some systems use nf_conntrack_ipv4 on older kernels

    # Set sysctl parameters
   tee /etc/sysctl.d/k8s.conf > /dev/null  << EOF
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    net.ipv4.conf.all.rp_filter = 0
    net.ipv4.conf.default.rp_filter = 0
EOF

    # Apply sysctl parameters
    sysctl --system > /dev/null 2>&1

    log INFO "System configured for Kubernetes"
}

# Configure containerd
configure_containerd() {
  log INFO "Configuring containerd"
  
  # Create the configuration file for containerd
  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml > /dev/null
  
  log INFO "Containerd configured"
}

# Configure kubelet
# This function configures the kubelet service to use the specified cgroup driver.
# It creates a systemd drop-in configuration file for kubelet and sets the necessary environment variables.
# The function also reloads the systemd daemon and restarts the kubelet service to apply the changes.
configure_kubelet(){
  log INFO "Configuring kubelet to use $CGROUP_DRIVER cgroup driver"
  
  # Create the kubelet configuration directory if it doesn't exist
  sudo mkdir -p /etc/systemd/system/kubelet.service.d/
  sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf > /dev/null << EOF
    # Note: This dropin only works with kubeadm and kubelet v1.11+
    [Service]
    Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
    Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
    Environment="KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix:///run/containerd/containerd.sock --cgroup-driver=${CGROUP_DRIVER}"
    # This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
    EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
    ExecStart=
    ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF
  # Create kubelet defaults file
  tee /etc/default/kubelet  > /dev/null  <<EOF
    KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///run/containerd/containerd.sock --cgroup-driver=${CGROUP_DRIVER}"
EOF
    
  # Reload the systemd daemon to recognize the new kubelet configuration
  sudo systemctl daemon-reload
  # Restart the kubelet service to apply the new configuration
  sudo systemctl restart kubelet
  # Enable the kubelet service to start on boot
  sudo systemctl enable kubelet
}

# Configure kubelet for cgroup driver
configure_kubeadm() {
  # Create the kubeadm configuration file
  sudo mkdir -p /etc/kubernetes
  
  # Create the kubeadm configuration file with the specified settings
  sudo   tee  /etc/kubernetes/kubeadm-config.yaml  > /dev/null << EOF
  apiVersion: kubeadm.k8s.io/v1beta4
  kind: InitConfiguration
  nodeRegistration:
    criSocket: unix:///run/containerd/containerd.sock
    name: $(hostname -s)
    kubeletExtraArgs:
      - name: cgroup-driver
        value: "$CGROUP_DRIVER"
  ---
  apiVersion: kubeadm.k8s.io/v1beta4
  kind: ClusterConfiguration
  kubernetesVersion: v${KUBERNETES_VERSION}
  controlPlaneEndpoint: "$CONTROL_PLANE_ENDPOINT"
  networking:
    podSubnet: "$POD_NETWORK_CIDR"
    serviceSubnet: "10.96.0.0/12"
  ---
  apiVersion: kubelet.config.k8s.io/v1beta1
  kind: KubeletConfiguration
  cgroupDriver: "$CGROUP_DRIVER"
EOF

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