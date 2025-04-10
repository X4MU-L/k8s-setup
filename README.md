# Kubernetes Installer

A utility script for automating the setup of Kubernetes clusters using kubeadm. This script handles prerequisites, container runtime installation, kubeadm setup, and proper cgroup configuration.

## Features

- Automatic detection of init system (systemd vs other)
- Automatic detection of cgroup version (v1 vs v2)
- Configures the appropriate cgroup driver (systemd or cgroupfs)
- Supports both master and worker node setup
- Handles all prerequisites (disabling swap, loading modules, etc.)
- Installs and configures containerd as the container runtime
- Supports specifying Kubernetes version
- Comprehensive logging
- Easy to install via Git and Make

## Prerequisites

- A Linux system with root access
- Ubuntu/Debian based distribution (primary support)
- Internet connectivity for downloading packages

## Installation

### Option 1: Direct Download

```bash
curl -fsSL https://raw.githubusercontent.com/X4MU-L/k8s-setup/main/install.sh | sudo bash
```

### Option 2: Clone Repository

```bash
git clone https://github.com/X4MU-L/k8s-setup.git
cd k8s-installer
sudo make install
```

## Usage

### Setting up a master node

```bash
sudo k8s-installer --node-type control-plane \
   --control-plane-endpoint k8s-master.example.com \
   --k8s-version <k8s_version> \
   --cni-provider  [cillium|calico] \
   --container-runtime-version <runtime_version>
```

### Setting up a worker node

```bash
sudo k8s-installer --node-type worker \
   --join-command kubeadm join .... \
   --k8s-version <k8s_version> \
   --cni-provider  [cillium|calico] \
   --container-runtime-version <runtime_version>

```

### Options

- `--node-type <TYPE>`: Specify node type (control-plane or worker)"
- `--k8s-version <VERSION>`: Kubernetes version to install (Optional)"
- `--container-runtime-version <VERSION>`: Container runtime version (Optional)"
- `--cilium-version <VERSION>`: Cilium CNI version (Optional)"
- `--cni-provider <PROVIDER>`: CNI provider cilium or calico, (Optional)"
- `--pod-network-cidr <CIDR>`: Pod network CIDR (Optional)"
- `--control-plane-endpoint <ENDPOINT>`: Control plane endpoint (required for control-plane)"
- `--join-command <COMMAND>`: Join command (required for worker nodes)"
- `--help Display this help message"

## How It Works

1. **Detection Phase**:

   - Checks system requirements and dependencies
   - Detects init system (systemd vs other)
   - Detects cgroup version (v1 vs v2)
   - Determines appropriate cgroup driver

2. **Preparation Phase**:

   - Disables swap
   - Loads required kernel modules
   - Sets necessary sysctl parameters
   - Checks required ports

3. **Installation Phase**:

   - Installs containerd with appropriate configuration
   - Installs kubeadm, kubelet, and kubectl
   - Configures kubelet to use the correct cgroup driver

4. **Cluster Setup Phase**:
   - For master: Initializes the control plane and installs Calico CNI
   - For worker: Joins an existing cluster using the provided join command

## Uninstallation

To uninstall the utility:

```bash
sudo make uninstall
```

Note: This will not uninstall Kubernetes components, only the installer utility.

## Logs

Logs are stored in `/var/log/k8s-installer/k8s-installer.log`

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
