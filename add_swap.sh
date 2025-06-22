#!/bin/bash
# This script is used to add swap space to a Linux system.
# It creates a swap file, sets the appropriate permissions, formats it as swap,
# and enables it.
# Usage: sudo ./add_swap.sh <size_in_MB>
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: sudo ./add_swap.sh <size_in_MB>"
    exit 1
fi

SWAP_SIZE="$1"
SWAP_FILE="/swapfile"
# Check if the swap file already exists
if [ -f "$SWAP_FILE" ]; then
    echo "Swap file already exists. Please remove it first."
    exit 1
fi
# Create a swap file of the specified size
echo "Creating swap file of size ${SWAP_SIZE}MB..."
fallocate -l "${SWAP_SIZE}M" "$SWAP_FILE" || {
    echo "Failed to create swap file. Please check your disk space."
    exit 1
}
# Set the correct permissions for the swap file
chmod 600 "$SWAP_FILE" || { 
    echo "Failed to set permissions on swap file."
    exit 1
}
# Format the file as swap
echo "Formatting swap file..."
mkswap "$SWAP_FILE" || {
    echo "Failed to format swap file."
    exit 1
}
# Enable the swap file
echo "Enabling swap file..."
swapon "$SWAP_FILE" || {
    echo "Failed to enable swap file."
    exit 1
}
# Add the swap file to /etc/fstab for persistence across reboots
echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab || {
    echo "Failed to add swap file to /etc/fstab."
    exit 1
}
