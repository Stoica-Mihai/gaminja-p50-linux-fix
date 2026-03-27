#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
