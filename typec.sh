#!/bin/sh

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

TARGET_VID="2207"
TARGET_PID="0006"

if lsusb | grep -q "${TARGET_VID}:${TARGET_PID}"; then
    log "INFO" "Detected USB device: VID=${TARGET_VID} PID=${TARGET_PID}"
    exit 0
else
    log "ERROR" "USB device not detected: VID=${TARGET_VID} PID=${TARGET_PID}"
    exit 1
fi