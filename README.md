# AZ08 Test Scripts

Production-line test scripts for the AZ08 hardware platform. Each script targets a specific hardware subsystem and returns exit code 0 (pass) or non-zero (fail).

## Test Item Analysis

| # | Test Item | Script | Timeout | Description |
|---|---|---|---|---|
| 1 | **SCREEN** | _(inline)_ | 30s | Touchscreen tap-to-confirm interaction |
| 2 | **KEY** | [`key.sh`](./key.sh) | 10s | Detects power, boot, and recovery key press events via input devices |
| 3 | **ADC** | [`adc.sh`](./adc.sh) | 10s | IIO ADC voltage measurement (ch3/4/5) + hardware configuration identification (CPU/DDR/eMMC/WiFi) against 12 known profiles |
| 4 | **AUDIO** | [`audio.py`](./audio.py) | 30s | ALSA loopback: generates 1 kHz sine wave, plays via `aplay`, records via `arecord`, compares dominant frequencies via FFT (max 3 retries) |
| 5 | **GPIO** | [`gpio.sh`](./gpio.sh) | 30s | 2-output + 20-input GPIO signal test (3 cycles with inverter logic) + UART 4-wire connectivity test (TX/RX, CTS/RTS) |
| 6 | **RTC** | [`rtc.sh`](./rtc.sh) | 10s | RTC device detection, time read/write, and 2-second tick verification |
| 7 | **SD Card** | [`sdcard.sh`](./sdcard.sh) | 10s | SD card detection (`/dev/mmcblk1`), mount, 4 KB random data write-back-read with `cmp` verification |
| 8 | **SPI Flash** | [`spi.sh`](./spi.sh) | 10s | Dual MTD device (`mtdblock0`/`mtdblock1`) erase, write, read-back, and `cmp` comparison |
| 9 | **USB** | [`usb_speedtest.sh`](./usb_speedtest.sh) | 30s | `fio` sequential read benchmark on USB mass storage (512 MB, 1 MB block, direct I/O, threshold ≥ 60 MB/s) |
| 10 | **Type-C** | [`typec.sh`](./typec.sh) | 10s | USB device presence check via `lsusb` matching VID=2207, PID=0006 |
| 11 | **eMMC** | [`emmc.sh`](./emmc.sh) | 10s | 64 MB random data write (`dd conv=fsync`), page cache drop, direct I/O read-back with integrity check and speed measurement |
| 12 | **RAM** | [`ram.py`](./ram.py) | 30s | Allocates 80% of available memory via `mmap`, writes repeating byte pattern, verifies every byte |
| 13 | **WiFi / BT** | [`wifibt.sh`](./wifibt.sh) | 30s | WiFi hotspot scan via `iwlist` + Bluetooth LE device scan via `hcitool lescan` |

## Execution Flow

```
SCREEN → KEY → ADC → AUDIO → GPIO → RTC → SDCard → SPI → USB → TYPE-C → eMMC → RAM → WiFi/BT
```

All tests run sequentially in a single thread. The pipeline stops on the first failure (`exit_on_error: true`).

## Hardware Interfaces Covered

| Category | Interfaces |
|---|---|
| **User Interaction** | Touchscreen, physical keys (power, boot, recovery) |
| **Analog** | ADC 6-channel (voltage sampling + hardware ID) |
| **Audio** | ALSA playback/record loopback (line in/out) |
| **GPIO** | 2 output + 20 input (with inverters) + 4 UART lines |
| **Storage** | eMMC, SD Card, SPI Flash (x2) |
| **Peripheral** | USB 3.0, Type-C (OTG detection) |
| **Wireless** | WiFi (802.11) + Bluetooth LE |
| **Clock** | RTC (Real-Time Clock) |
| **Memory** | DDR (pattern write/read verification) |

## GPIO Pin Mapping

See the comment header in [`gpio.sh`](./gpio.sh) for the complete 26-pin mapping table including all network labels, GPIO pins, and sysfs numbers.
