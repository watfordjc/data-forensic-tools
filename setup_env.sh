#!/bin/bash

# 1. Configure Git to use the tracked hooks directory
echo "Configuring local repository settings..."
git config --local core.hooksPath hooks
git config --local commit.gpgSign true

# 2. Check for required binaries
DEPENDENCIES=(adb curl jq openssl shellcheck gpg)

echo "Checking for required tools..."
for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Missing: $cmd is not installed."
        read -p "Would you like to attempt to install $cmd? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo apt update && sudo apt install -y "$cmd"
        else
            echo "Please install $cmd manually to use this toolset."
        fi
    else
        echo "Found: $(command -v "$cmd")"
    fi
done

echo "Environment setup complete."

GITHUB_KEY_ID="BF09A195A052493F80975092380852F8F6CE9235"

echo "Checking for GitHub Signing Key ($GITHUB_KEY_ID)..."
if ! gpg --list-keys "$GITHUB_KEY_ID" &> /dev/null; then
    echo "Warning: Your GitHub signing key is not in the local keyring."
    echo "Commit signing will fail until you import it."
else
    echo "Confirmed: Signing key is present and available."
    git config --local user.signingkey "$GITHUB_KEY_ID"
fi

# Add this to your setup_env.sh
echo "Initializing submodules..."
git submodule update --init --recursive
