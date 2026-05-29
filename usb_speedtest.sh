#!/bin/bash

set -euo pipefail

USB3_MIN_READ_SPEED=60
USB2_MIN_READ_SPEED=10

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

if ! command -v fio >/dev/null 2>&1; then
    log "ERROR" "fio is not installed. Please install fio first."
    exit 1
fi

find_usb_block_devs_by_ctrl() {
    local ctrl="$1"
    for link in /sys/block/sd*; do
        if [ -L "$link" ] && readlink -f "$link" | grep -q "$ctrl"; then
            basename "$link"
            return 0
        fi
    done
    return 1
}

declare -A ctrl_min_read=(
    ["23400000"]=$USB3_MIN_READ_SPEED
)
ctrls=("23400000")

declare -A devs
all_found=1
for ctrl in "${ctrls[@]}"; do
    dev=$(find_usb_block_devs_by_ctrl "$ctrl" || true)
    if [ -z "$dev" ]; then
        log "ERROR" "No USB device detected under USB controller $ctrl"
        all_found=0
    else
        log "INFO" "Device detected under USB controller $ctrl: $dev"
        devs["$ctrl"]="$dev"
    fi
done

if [ "$all_found" -ne 1 ]; then
    log "ERROR" "A USB device must be detected under all three USB controllers"
    exit 1
fi

pass=1
for ctrl in "${ctrls[@]}"; do
    device="/dev/${devs[$ctrl]}"
    min_read="${ctrl_min_read[$ctrl]}"
    log "INFO" "Testing $device (USB controller $ctrl, min read: ${min_read}MB/s)"

    fio_output=$(fio --name=usb-read-test \
        --filename="$device" \
        --rw=read \
        --bs=1M \
        --size=512M \
        --direct=1 \
        --runtime=5 \
        --time_based \
        --output-format=terse 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$fio_output" ]; then
        log "ERROR" "Read test failed: $device"
        pass=0
        continue
    fi

    read_speed=$(echo "$fio_output" | awk -F';' '{ printf("%.2f", $7/1024) }')
    read_speed_int=$(printf "%.0f" "$read_speed")

    if [ -n "$read_speed" ]; then
        log "INFO" "$device Read speed: ${read_speed} MB/s"
        if [ "$read_speed_int" -ge "$min_read" ]; then
            log "INFO" "$device (USB controller $ctrl) test PASSED"
        else
            log "ERROR" "$device (USB controller $ctrl) read speed does not meet requirement (Read: $read_speed, min: $min_read)"
            pass=0
        fi
    else
        log "ERROR" "Failed to get read speed for $device (USB controller $ctrl)"
        pass=0
    fi
done

if [ "$pass" -eq 1 ]; then
    log "INFO" "All USB read speed tests passed"
    exit 0
else
    log "ERROR" "Some USB read speed tests failed"
    exit 1
fi
