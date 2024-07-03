#!/bin/bash
# Author: Aman Shanbhag
# Description: This script will install git and git-lfs, if not already installed

set -e

apt-get update && apt-get install -y curl 
apt-get install -y wget

# Function to check if git is installed
check_git() {
    if command -v git &>/dev/null; then
        echo "git is already installed"
        return 0
    else
        echo "git is not installed"
        return 1
    fi
}

# Function to check if git-lfs is installed
check_git_lfs() {
    if command -v git-lfs &>/dev/null; then
        echo "git-lfs is already installed"
        return 0
    else
        echo "git-lfs is not installed"
        return 1
    fi
}

if check_git; then  #0
    echo "Git is already installed"
    git --version
    if check_git_lfs; then  #0
        echo "Git-lfs is already installed"
        git-lfs --version
    else  #1
        echo "Installing git-lfs"
        apt-get update && apt-get install -y git-lfs
        echo "Installed git-lfs"
    fi
else
    apt-get update && apt-get install -y git
    apt-get install -y git-lfs
fi    
