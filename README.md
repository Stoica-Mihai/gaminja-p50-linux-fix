# Gaminja P50 Linux Fix

Linux kernel driver fix for the Gaminja P50 and other third-party DualSense clone controllers.

## The Problem

Third-party DualSense-compatible controllers (like the Gaminja P50) use Sony's vendor/product IDs (`054c:0ce6`) but don't fully implement the DualSense protocol. On Linux, the `hid-playstation` kernel driver claims these devices but fails during probe:

```
playstation 0003:054C:0CE6.XXXX: Invalid byte count transferred, expected 20 got 16
playstation 0003:054C:0CE6.XXXX: Failed to retrieve DualSense pairing info: -22
playstation 0003:054C:0CE6.XXXX: Failed to get MAC address from DualSense
playstation 0003:054C:0CE6.XXXX: Failed to create dualsense.
playstation 0003:054C:0CE6.XXXX: probe with driver playstation failed with error -22
```

The controller is detected but doesn't work — no input, no gamepad, nothing.

On top of that, the HID core's built-in device table marks this vendor/product ID as having a special driver (`HID_QUIRK_HAVE_SPECIAL_DRIVER`), which prevents `hid-generic` from picking it up as a fallback.

## What This Fix Does

This is a patched `hid-playstation` kernel module, installed via DKMS so it survives kernel updates. It fixes:

1. **USB probe failure** — The driver expects a 20-byte pairing info response, but clone controllers return 16 bytes. The fix accepts any response >= 7 bytes (report ID + 6-byte MAC address), which is all the driver actually needs.

2. **Bluetooth ghost inputs** — Clone controllers interleave non-input data reports on the same BT report ID as real input. The fix detects these by checking the sub-type field in byte 1 and neutralizes them with idle data (centered sticks, no buttons pressed).

3. **Bluetooth CRC failures** — Clone controllers don't compute valid DualSense BT CRCs. The fix skips CRC validation for detected clone controllers.

4. **Phantom touchpad clicks** — The touchpad byte offsets in BT reports contain garbage data, causing phantom touch events and erratic clicking. The fix disables touchpad input on BT for clone controllers.

All fixes are gated behind an `is_clone_controller` flag that is only set when the pairing info response is shorter than expected. **Real Sony DualSense controllers are completely unaffected.**

## Compatibility

| Feature | USB | Bluetooth |
|---------|-----|-----------|
| Gamepad (sticks, buttons, triggers, d-pad) | Working | Working |
| Touchpad | Working | Disabled (hardware sends garbage data) |
| Motion sensors | Working | Working |
| Rumble | Working | Working |
| Headset jack detection | Working | Working |

Tested on:
- Gaminja P50 Controller (YLW Tech, `054c:0ce6`)
- Arch Linux / CachyOS with kernel 6.19.x
- Should work on any Linux distribution with DKMS support and kernel 6.x+

## Installation

### Prerequisites

- Kernel headers for your running kernel
- DKMS
- Build tools (gcc, make)

On Arch Linux:
```bash
sudo pacman -S dkms base-devel linux-headers
# or for CachyOS:
sudo pacman -S dkms base-devel linux-cachyos-bore-headers
```

On Ubuntu/Debian:
```bash
sudo apt install dkms build-essential linux-headers-$(uname -r)
```

On Fedora:
```bash
sudo dnf install dkms kernel-devel
```

### Install

```bash
git clone https://github.com/Stoica-Mihai/gaminja-p50-linux-fix.git
cd gaminja-p50-linux-fix
./install.sh
```

The install script copies the source to `/usr/src/`, builds via DKMS, installs, and loads the module. Verify it worked:

```bash
modinfo hid_playstation | head -1
# Should show: filename: /lib/modules/.../updates/dkms/hid-playstation.ko.zst
```

### Rebuild After Editing

If you modify the source, just run `./install.sh` again — it handles both first-time install and rebuilds.

### Uninstall

The install script automatically backs up the original kernel module to `./backup/` on first run. To uninstall:

```bash
sudo dkms remove hid-playstation-fix/1.0 --all
```

Then restore the original module from the backup:

```bash
sudo cp ./backup/hid-playstation.ko* /usr/lib/modules/$(uname -r)/kernel/drivers/hid/
sudo depmod -a
sudo modprobe hid_playstation
```

If the backup is missing, restore from your distribution's package:

```bash
# Arch Linux / CachyOS:
sudo pacman -S linux-cachyos-bore  # or your kernel package name

# Ubuntu/Debian:
sudo apt reinstall linux-modules-$(uname -r)

# Fedora:
sudo dnf reinstall kernel-modules-$(uname -r)
```

## Bluetooth Pairing

If you have trouble pairing over Bluetooth:

1. Make sure the `hidp` module is loaded:
   ```bash
   sudo modprobe hidp
   # To load at boot:
   echo "hidp" | sudo tee /etc/modules-load.d/hidp.conf
   ```

2. Put the controller in pairing mode (usually PS + Share held for 5 seconds until the light bar blinks rapidly).

3. Pair using `bluetoothctl`:
   ```bash
   bluetoothctl scan on
   # Wait for the controller to appear, then:
   bluetoothctl pair <MAC_ADDRESS>
   bluetoothctl trust <MAC_ADDRESS>
   bluetoothctl connect <MAC_ADDRESS>
   ```

4. If the controller connects but no input works, the pairing may have used BLE instead of classic Bluetooth. Try clearing the Bluetooth cache:
   ```bash
   sudo systemctl stop bluetooth
   sudo rm -rf /var/lib/bluetooth/<ADAPTER_MAC>/cache/*
   sudo systemctl start bluetooth
   ```
   Then remove and re-pair the controller.

## How Clone Controllers Are Detected

The fix detects clone controllers during the USB/BT probe by checking the size of the pairing info feature report response:

- **Real DualSense**: Returns exactly 20 bytes -> `is_clone_controller = false`
- **Clone controllers**: Returns fewer bytes (e.g., 16) -> `is_clone_controller = true`

This detection is automatic. No configuration or manual flags are needed.

## Technical Details

### Patched Function: `dualsense_get_mac_address()`

The original function calls `ps_get_report()` which enforces an exact 20-byte response. The fix calls `hid_hw_raw_request()` directly and accepts any response >= 7 bytes.

### BT Report Filtering

Clone controllers send two types of BT reports on report ID `0x31`:

- **Type 1** (`data[1] & 0x0F == 0x01`): Valid gamepad input, identical layout to real DualSense
- **Type 2** (`data[1] & 0x0F == 0x02`): Non-input data (telemetry/sensor stream) that produces garbage when parsed as input

Type 2 reports are detected and overwritten with neutral idle data (centered sticks, no buttons, inactive touchpad contacts) before they reach the input subsystem or hidraw/Steam.

### CRC Handling

Real DualSense controllers compute CRC32 over BT input reports. Clone controllers don't. The fix skips CRC validation for clone controllers to prevent all BT reports from being dropped.

## Other Gaminja Controllers

If you have a **Gaminja NS009** (Switch-style controller), it works on Linux without kernel patches:

- **USB**: Plug in, auto-detected as Xbox 360 pad
- **Bluetooth**: Pair with **Y + HOME** (hold 3 seconds) for Switch Pro Controller mode

## License

This module is based on the Linux kernel's `hid-playstation.c` and is licensed under GPL v2, same as the original.

## Acknowledgments

- Original `hid-playstation` driver by Sony Interactive Entertainment
- DualSense protocol documentation from the Linux kernel and community
