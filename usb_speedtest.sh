#!/bin/bash

set -euo pipefail

USB3_MIN_READ_SPEED=60

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

usb_link_speed_for_block() {
    local p
    p="$(readlink -f "/sys/block/$1" 2>/dev/null)" || return 1
    while [ -n "$p" ] && [ "$p" != "/" ]; do
        if [ -f "$p/speed" ] && [ -f "$p/idVendor" ]; then
            cat "$p/speed"
            return 0
        fi
        p="$(dirname "$p")"
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
    log "ERROR" "A USB mass storage device must be detected under the USB 3.0 controller"
    exit 1
fi

pass=1
for ctrl in "${ctrls[@]}"; do
    device="/dev/${devs[$ctrl]}"
    min_read="${ctrl_min_read[$ctrl]}"

    link_speed="$(usb_link_speed_for_block "${devs[$ctrl]}" 2>/dev/null || true)"
    log "INFO" "$device USB link speed: ${link_speed:-unknown} Mbps"
    if [ "$link_speed" != "5000" ]; then
        log "ERROR" "$device link trained at ${link_speed:-unknown} Mbps, not 5000 (SuperSpeed)"
        log "ERROR" "This is a link fault, not a storage fault -- do not swap the stick first."
        pass=0
        continue
    fi

    log "INFO" "Testing $device (USB controller $ctrl, min read: ${min_read}MB/s)"

    fio_err="$(mktemp)"
    fio_rc=0
    fio_output=$(fio --name=usb-read-test \
        --filename="$device" \
        --rw=read \
        --bs=1M \
        --size=512M \
        --direct=1 \
        --runtime=5 \
        --time_based \
        --output-format=terse 2>"$fio_err") || fio_rc=$?

    if [ "$fio_rc" -ne 0 ] || [ -z "$fio_output" ]; then
        log "ERROR" "Read test failed: $device (fio exit ${fio_rc}): $(tr '\n' ' ' < "$fio_err")"
        rm -f "$fio_err"
        pass=0
        continue
    fi
    rm -f "$fio_err"

    read_speed=$(echo "$fio_output" | awk -F';' 'NF>=7 { printf("%.2f", $7/1024); exit }')
    case "$read_speed" in
        ''|*[!0-9.]*) read_speed="" ;;
    esac
    read_speed_int=$(printf "%.0f" "${read_speed:-0}")

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
    log "INFO" "USB read speed test passed"
    exit 0
else
    log "ERROR" "USB read speed test failed"
    exit 1
fi
