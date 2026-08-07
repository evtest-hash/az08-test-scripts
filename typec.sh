#!/bin/bash
#
# Type-C (OTG0, gadget) is cabled to a hub on the on-board USB-A host (OTG1),
# so the board enumerates itself. SuperSpeed and USB 2.0 are separate physical
# paths and a trained SS link never uses D+/D-, so two passes are needed:
#   Pass A  speed == 5000 -> pins 107/108/110/111 + 119/120/122/123
#   Pass B  speed == 480  -> pins 116/117 + 125/126
# Enumerating at all covers pins 128 and 114. Total 14/18; 105/113/137/138 are
# not reachable by a self-loop and need ICT.
#
# Pass B caps the gadget's own max_speed rather than disabling a USB port:
# disabling a port behind an external hub cuts that port's VBUS, which detaches
# the gadget completely instead of dropping it to USB 2.0.

VENDOR_ID="${VENDOR_ID:-2207}"
SPEED_SS="5000"
SPEED_HS="480"
ENUM_TIMEOUT="${ENUM_TIMEOUT:-10}"
DEFAULT_MAX_SPEED="${DEFAULT_MAX_SPEED:-super-speed-plus}"
LOCK_FILE="${LOCK_FILE:-/tmp/.az08_usb_bus.lock}"

USB_DEVICES="/sys/bus/usb/devices"
GADGET_DIR=""
ORIG_MAX_SPEED=""
SPEED_FORCED=0

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

# The gadget re-enumeration in Pass B perturbs the hub uplink that
# usb_speedtest.sh measures throughput on. Both scripts take this lock.
acquire_usb_lock() {
    if ! command -v flock >/dev/null 2>&1; then
        log "WARN" "flock not available; running without the USB bus mutex"
        return 0
    fi
    exec 9>"$LOCK_FILE" 2>/dev/null || return 0
    if ! flock -n 9 2>/dev/null; then
        log "INFO" "Another USB test holds ${LOCK_FILE}, waiting..."
        flock 9
    fi
    log "INFO" "Holding USB bus lock ${LOCK_FILE}"
}

find_usb_dev() {
    local d vid class
    for d in "${USB_DEVICES}"/*; do
        [ -f "${d}/idVendor" ] || continue
        vid="$(cat "${d}/idVendor" 2>/dev/null)"
        [ "$vid" = "$VENDOR_ID" ] || continue
        class="$(cat "${d}/bDeviceClass" 2>/dev/null)"
        [ "$class" = "09" ] && continue
        echo "$d"
        return 0
    done
    return 1
}

wait_for_speed() {
    local want="$1" waited=0 dev speed
    while [ "$waited" -lt "$ENUM_TIMEOUT" ]; do
        dev="$(find_usb_dev)"
        if [ -n "$dev" ]; then
            speed="$(cat "${dev}/speed" 2>/dev/null)"
            if [ "$speed" = "$want" ]; then
                echo "$dev"
                return 0
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

describe_dev() {
    local dev="$1"
    log "INFO" "  path       : ${dev}"
    log "INFO" "  idVendor   : $(cat "${dev}/idVendor" 2>/dev/null)"
    log "INFO" "  idProduct  : $(cat "${dev}/idProduct" 2>/dev/null)"
    log "INFO" "  speed      : $(cat "${dev}/speed" 2>/dev/null) Mbps"
    log "INFO" "  product    : $(cat "${dev}/product" 2>/dev/null)"
    log "INFO" "  controller : $(readlink -f "${dev}/.." 2>/dev/null)"
}

# Cleans up after an older revision of this script that disabled ports.
recover_missing_gadget() {
    [ -z "$(find_usb_dev)" ] || return 0
    local p n=0
    for p in "${USB_DEVICES}"/*/*/*-port*/disable; do
        [ -w "$p" ] || continue
        [ "$(cat "$p" 2>/dev/null)" = "1" ] || continue
        log "WARN" "Gadget missing and $(basename "$(dirname "$p")") is disabled, re-enabling"
        echo 0 > "$p" 2>/dev/null && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && sleep 3
    return 0
}

find_gadget_dir() {
    local g
    for g in /sys/kernel/config/usb_gadget/*; do
        [ -f "$g/max_speed" ] || continue
        [ -n "$(cat "$g/UDC" 2>/dev/null)" ] || continue
        echo "$g"
        return 0
    done
    return 1
}

# max_speed is rejected while the gadget is bound; the read-back guards against
# a uevent handler rebinding underneath us.
set_gadget_max_speed() {
    local want="$1" udc cur try
    udc="$(cat "${GADGET_DIR}/UDC" 2>/dev/null)"
    if [ -z "$udc" ]; then
        log "ERROR" "Gadget $(basename "$GADGET_DIR") is not bound to a UDC"
        return 1
    fi

    for try in 1 2 3; do
        echo "" > "${GADGET_DIR}/UDC" 2>/dev/null
        echo "$want" > "${GADGET_DIR}/max_speed" 2>/dev/null
        cur="$(cat "${GADGET_DIR}/max_speed" 2>/dev/null)"
        [ "$cur" = "$want" ] && break
        sleep 1
    done

    echo "$udc" > "${GADGET_DIR}/UDC" 2>/dev/null
    if [ "$cur" != "$want" ]; then
        log "ERROR" "Failed to set max_speed to '${want}' (still '${cur}')"
        return 1
    fi
    log "INFO" "Gadget max_speed = ${cur}, re-attached to ${udc}"
    return 0
}

restore_gadget_speed() {
    [ "$SPEED_FORCED" = "1" ] || return 0
    SPEED_FORCED=0
    set_gadget_max_speed "$ORIG_MAX_SPEED" || return 1
    if [ -n "$(wait_for_speed "$SPEED_SS")" ]; then
        log "INFO" "SuperSpeed link restored"
    else
        log "WARN" "SuperSpeed did not recover within ${ENUM_TIMEOUT}s; the next run will report it"
    fi
}
trap restore_gadget_speed EXIT INT TERM

# A killed run leaves max_speed capped, which Pass A would misreport as a
# SuperSpeed failure.
ensure_superspeed_baseline() {
    local cur
    cur="$(cat "${GADGET_DIR}/max_speed" 2>/dev/null)"
    case "$cur" in
        super-speed*)
            ORIG_MAX_SPEED="$cur"
            return 0
            ;;
    esac
    log "WARN" "Gadget max_speed is '${cur}' (previous run interrupted); restoring ${DEFAULT_MAX_SPEED}"
    ORIG_MAX_SPEED="$DEFAULT_MAX_SPEED"
    set_gadget_max_speed "$DEFAULT_MAX_SPEED"
}

check_gadget() {
    local udc state
    udc="$(ls /sys/class/udc 2>/dev/null | head -n 1)"
    if [ -z "$udc" ]; then
        log "ERROR" "No UDC found -- usb_drd0_dwc3 registered no gadget controller"
        return 1
    fi
    state="$(cat "/sys/class/udc/${udc}/state" 2>/dev/null)"
    log "INFO" "UDC ${udc} state: ${state}"
    if [ "$state" != "configured" ]; then
        log "ERROR" "Gadget not configured (state=${state}); the host side cannot enumerate it"
        return 1
    fi

    GADGET_DIR="$(find_gadget_dir)"
    if [ -z "$GADGET_DIR" ]; then
        log "ERROR" "No configfs gadget bound to a UDC"
        return 1
    fi
    # PID follows the enabled function set (adb=0x0006, adb-ums=0x0018 ...), so
    # it is reported but never matched on.
    log "INFO" "Gadget $(basename "$GADGET_DIR"): idVendor=$(cat "${GADGET_DIR}/idVendor" 2>/dev/null) idProduct=$(cat "${GADGET_DIR}/idProduct" 2>/dev/null) max_speed=$(cat "${GADGET_DIR}/max_speed" 2>/dev/null)"
    return 0
}

check_vbus_switches() {
    local summary="/sys/kernel/debug/regulator/regulator_summary"
    if [ ! -r "$summary" ]; then
        log "WARN" "${summary} not readable, skipping VBUS switch check"
        return 0
    fi
    log "INFO" "VBUS switch state:"
    grep -E 'vbus5v0_(host|typec)' "$summary" | while read -r line; do
        log "INFO" "  ${line}"
    done
    return 0
}

pass_a_superspeed() {
    log "INFO" "==> Pass A: SuperSpeed enumeration (covers the 8 SS pins)"
    local dev
    dev="$(wait_for_speed "$SPEED_SS")"
    if [ -z "$dev" ]; then
        dev="$(find_usb_dev)"
        if [ -z "$dev" ]; then
            log "ERROR" "No device with idVendor=${VENDOR_ID} enumerated within ${ENUM_TIMEOUT}s"
            log "ERROR" "Both data paths suspect, or VBUS missing (pin 128 USB_OTG1_PWREN / pin 114 USB2_OTG0_DET)"
        else
            log "ERROR" "Enumerated at $(cat "${dev}/speed" 2>/dev/null) Mbps, expected ${SPEED_SS}"
            log "ERROR" "SuperSpeed link failed -- check pins 107/108/110/111 (OTG0) and 119/120/122/123 (OTG1)"
            describe_dev "$dev"
        fi
        return 1
    fi
    log "INFO" "SuperSpeed link up:"
    describe_dev "$dev"
    return 0
}

pass_b_highspeed() {
    log "INFO" "==> Pass B: gadget capped at high-speed (covers the 4 DP/DM pins)"

    local dev rc=0
    SPEED_FORCED=1
    if ! set_gadget_max_speed high-speed; then
        SPEED_FORCED=0
        log "ERROR" "Could not cap the gadget at high-speed; DP/DM remain unverified"
        return 1
    fi

    dev="$(wait_for_speed "$SPEED_HS")"
    if [ -z "$dev" ]; then
        dev="$(find_usb_dev)"
        if [ -z "$dev" ]; then
            log "ERROR" "Gadget did not re-enumerate on USB 2.0 within ${ENUM_TIMEOUT}s"
            log "ERROR" "DP/DM suspect -- check pins 116/117 (OTG0) and 125/126 (OTG1)"
        else
            log "ERROR" "Re-enumerated at $(cat "${dev}/speed" 2>/dev/null) Mbps, expected ${SPEED_HS}"
            describe_dev "$dev"
        fi
        rc=1
    else
        log "INFO" "High-speed link up:"
        describe_dev "$dev"
    fi

    restore_gadget_speed
    return $rc
}

main() {
    local rc=0

    log "INFO" "==> Type-C self-loop test (VID=${VENDOR_ID})"
    acquire_usb_lock
    recover_missing_gadget

    if ! check_gadget; then
        rc=1
    fi
    check_vbus_switches

    if [ $rc -eq 0 ]; then
        ensure_superspeed_baseline
        pass_a_superspeed || rc=1
    else
        log "ERROR" "Skipping Pass A: gadget side is not ready"
    fi

    if [ $rc -eq 0 ]; then
        pass_b_highspeed || rc=1
    else
        log "ERROR" "Skipping Pass B"
    fi

    if [ $rc -eq 0 ]; then
        log "INFO" "Type-C test PASSED (14/18 core board USB pins covered)"
    else
        log "ERROR" "Type-C test FAILED"
    fi
    return $rc
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi
