# openHop Repeater for the Femtofox

Custom Armbian Linux image builder for the **Femtofox**, preconfigured with the **openHop Repeater** software — a LoRa mesh repeater daemon with a web dashboard.

Based on [Armbian](https://www.armbian.com/) build framework (v26.2.1) running Debian Bookworm (minimal, vendor kernel).

For more information about the Femtofox see [femtofox](https://github.com/femtofox/femtofox)


Click below to download the latest release:

[![Release](https://img.shields.io/github/v/release/theshaun/openhop-femtofox?include_prereleases)](https://github.com/theshaun/openhop-femtofox/releases/latest)


## Hardware

- **Board**: FemtoFox with a Luckfox Pico Mini (Rockchip RV1103B, Cortex-A7)
- **RAM**: 64MB
- **Storage**: MicroSD card
- **Radio**: SX1262-based LoRa modules (1W or 2W FemtoFox profiles included)


## Flashing


```bash
xz -d openHop_Repeater_FemtoFox_2026.06.1.img.xz
sudo dd if=openHop_Repeater_FemtoFox_2026.06.1.img of=/dev/sdX bs=4M status=progress
sync
```

Windows: Use [Rufus](https://rufus.ie/) or [balenaEtcher](https://etcher.balena.io/).

## First Boot

1. Insert SD card and power on
3. Login as `root` with the configured password (default is `changeme`)
4. Armbian will prompt you to (very slowly on this first boot, be patient!):
   - Create a user account
   - Set timezone/locale (auto-detected)
5. Root is locked after first login

## Usage

### Web Dashboard

```
http://<device-ip>:8000
```

### Service Management

```bash
sudo systemctl status openhop-repeater
sudo systemctl restart openhop-repeater
sudo journalctl -u openhop-repeater -f
```

### Radio Configuration

Radio hardware profiles are in `/opt/openhop_repeater/openhop_repeater/radio-settings.json`:

| Profile | Module | Power |
|---------|--------|-------|
| `femtofox-1W-SX` | SX1262 1W | 30 dBm |
| `femtofox-2W-SX` | SX1262 2W | 8 dBm (DIO2 RF switch forcing to 33 dBm) |

Main config: `/etc/openhop_repeater/config.yaml`

### Serial Console

- **Baud**: 115200
- **Pins**: TX, RX, GND on UART4
- **Voltage**: 3.3V (use USB-to-TTL adapter)

> [!NOTE]
Only basic testing has been performed. Wifi and RTC clocks etc may not work yet


## Build Options

Three ways to build the image locally:

### WSL2 (Recommended for Windows)

```bash
# In WSL terminal
cd /mnt/c/GIT/openhop-femtofox
sudo bash wsl-openhop-build.sh
```

Output: `C:\GIT\openhop-femtofox\output\`

### Docker

```bash
bash docker-build.sh
```

### Native Linux

```bash
bash build.sh
```

## Configuration

All build settings are in `config.env`:

| Setting | Default | Description |
|---------|---------|-------------|
| `BUILD_REVISION` | `1` | Revision number (increment per build in same month) |
| `HOSTNAME` | `femtofox` | Device hostname |
| `TIMEZONE` | `UTC` | System timezone |
| `LUCKFOX_PASSWORD` | `changeme` | Root password for first boot |
| `LUCKFOX_SSH_KEY` | *(empty)* | Optional SSH authorized key |
| `OPENHOP_REPO` | GitHub URL | openHop Repeater git repository |
| `OPENHOP_BRANCH` | `main` | Branch to build from |
| `OUTPUT_NAME` | `openHop_Repeater_FemtoFox` | Output image name prefix |
| `SWAP_SIZE_MB` | `256` | Swap file size in MB |
| `SWAPPINESS` | `10` | Kernel swappiness value |
| `ARMBIAN_TAG` | `v26.2.1` | Armbian build framework version |
| `ARMBIAN_RELEASE` | `bookworm` | Debian release |
| `ARMBIAN_BOARD` | `luckfox-pico-mini` | Target board |
| `ARMBIAN_BRANCH` | `vendor` | Kernel branch |

## License

openHop Repeater is MIT licensed. Armbian is GPL-2.0.
