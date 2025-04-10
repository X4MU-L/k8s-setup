#!/bin/bash

# Get project name from argument or use default
PROJECT_NAME=${1:-"k8s-installer"}
# Repository information
REPO_URL="https://github.com/X4MU-L/k8s-setup"
BRANCH="main"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
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
    if ! git clone --branch "$BRANCH" "$REPO_URL" "$TMP_DIR/repo"; then
        echo "Git clone failed, falling back to archive download..."
        if ! curl -L "$REPO_URL/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMP_DIR"; then
            echo "Archive download failed"
            rm -rf "$TMP_DIR"
            exit 1
        fi
        mv "$TMP_DIR"/*-"$BRANCH" "$TMP_DIR/repo"
    fi
else
    echo "Git not found, using archive download ..."
    if ! curl -L "$REPO_URL/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMP_DIR"; then
        echo "Archive download failed"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    mv "$TMP_DIR"/*-"$BRANCH" "$TMP_DIR/repo"
fi

# Change to repo directory
cd "$TMP_DIR/repo" || {
    echo "Failed to change to repository directory"
    rm -rf "$TMP_DIR"
    exit 1
}

if [ -f "Makefile" ]; then
    # No need for sudo here since we're already root
    make uninstall PROJECT_NAME="$PROJECT_NAME"
    rm -rf "$TMP_DIR"
    echo "Uninstallation of $PROJECT_NAME complete"

else
    echo "Makefile not found, installation failed"
    rm -rf "$TMP_DIR"
    exit 1
fi