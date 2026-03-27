#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_MOD=$(find /usr/lib/modules/$(uname -r) -name "hid-playstation.ko*" -not -path "*/updates/*" 2>/dev/null | head -1)
BACKUP_DIR="$SCRIPT_DIR/backup"

# Backup original kernel module if not already backed up
if [ -n "$KERNEL_MOD" ] && [ ! -d "$BACKUP_DIR" ]; then
    echo "Backing up original module to $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp "$KERNEL_MOD" "$BACKUP_DIR/"
    echo "Backup saved: $BACKUP_DIR/$(basename "$KERNEL_MOD")"
elif [ -d "$BACKUP_DIR" ]; then
    echo "Backup already exists in $BACKUP_DIR, skipping."
fi

echo "Copying source to /usr/src/hid-playstation-fix-1.0/..."
sudo mkdir -p /usr/src/hid-playstation-fix-1.0/
sudo cp "$SCRIPT_DIR"/hid-playstation.c "$SCRIPT_DIR"/hid-ids.h "$SCRIPT_DIR"/Makefile "$SCRIPT_DIR"/dkms.conf /usr/src/hid-playstation-fix-1.0/

echo "Building and installing DKMS module..."
sudo dkms add hid-playstation-fix/1.0 2>/dev/null || true
sudo dkms build hid-playstation-fix/1.0 --force
sudo dkms install hid-playstation-fix/1.0 --force

echo "Loading module..."
sudo modprobe -r hid_playstation 2>/dev/null || true
sudo modprobe hid_playstation

echo "Done. Reconnect your controller."
