#!/usr/bin/env bash

# k8s-installer install script
# This script downloads and installs the k8s-installer utility

# Get project name from argument or use default
PROJECT_NAME=${1:-"k8s-installer"}

# Repository information
REPO_URL="https://github.com/X4MU-L/k8s-setup"
BRANCH="main"
INSTALL_DIR="/usr/local/lib/$PROJECT_NAME"
BIN_DIR="/usr/local/bin"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Check if project is already installed
if [ -d "$INSTALL_DIR" ]; then
    echo "Project is already installed..."
    echo "Run sudo make uninstall to uninstall"
    exit 1
fi

# Create temporary directory
TMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
    echo "Failed to create temporary directory"
    exit 1
fi

# Clone repository or download archive
echo "Downloading repository..."
if command -v git >/dev/null 2>&1; then
    if ! git clone --branch "$BRANCH" "$REPO_URL" "$TMP_DIR/repo" >/dev/null; then
        # Fallback to archive download if git clone fails
        echo "Git clone failed, falling back to archive download..."
        if ! curl -L "$REPO_URL/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMP_DIR"; then
            echo "Archive download failed"
            rm -rf "$TMP_DIR"
            exit 1
        fi
        # Move the extracted directory to the repo directory
        mv "$TMP_DIR"/*-"$BRANCH" "$TMP_DIR/repo"
    fi
else
    # if git is not found, use archive download
    echo "Git not found, using archive download ..."
    if ! curl -L "$REPO_URL/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMP_DIR"; then
        echo "Archive download failed"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    # Move the extracted directory to the repo directory
    mv "$TMP_DIR"/*-"$BRANCH" "$TMP_DIR/repo"
fi

# Change to repo directory
cd "$TMP_DIR/repo" || {
    echo "Failed to change to repository directory"
    rm -rf "$TMP_DIR"
    exit 1
}

# Run make install
if [ -f "Makefile" ]; then
    # Run make install with project name
    if ! command -v make >/dev/null 2>&1; then
    echo "'make' is not installed. Attempting to install..."
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y make
        else
            echo "Automatic installation not supported on this OS. Please install 'make' manually."
            exit 1
        fi
    fi
    make install PROJECT_NAME="$PROJECT_NAME" 2>&1 | grep -v "make: \*\*\*"
    # check if make install was successful
    if [ $? -ne 0 ]; then
        echo "Installation failed"
        # Cleanup
        echo "Cleaning up..."
        rm -rf "$TMP_DIR"
        exit 1
    fi
else
    echo "Makefile not found, installation failed"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Cleanup
rm -rf "$TMP_DIR"
echo "Installation completed successfully!"
echo "You can now use '$PROJECT_NAME' command to set up Kubernetes"
echo "Examples:"
echo "  sudo $PROJECT_NAME --role master --version 1.28.0"
echo "  sudo $PROJECT_NAME --role worker"

