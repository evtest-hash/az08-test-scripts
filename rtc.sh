log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

test_rtc() {
    log "INFO" "==> Checking RTC..."
    if [ ! -e "/dev/rtc0" ]; then
        log "ERROR" "RTC device /dev/rtc0 not found"
        return 1
    fi

    log "INFO" "Detected /dev/rtc0"

    old_rtc_time=$(hwclock -r -f /dev/rtc0 2>/dev/null )
    if [ -z "$old_rtc_time" ]; then
        log "ERROR" "Failed to read RTC time"
        return 2
    fi
    log "INFO" "Current RTC time: $old_rtc_time"

    sys_time=$(date "+%Y-%m-%d %H:%M:%S")
    log "INFO" "Setting RTC time to: $sys_time"

    hwclock -w -f /dev/rtc0 2>/dev/null
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to write RTC time"
        return 3
    fi

    sleep 2

    new_rtc_time=$(hwclock -r -f /dev/rtc0 2>/dev/null )
    log "INFO" "RTC time after 2 seconds: $new_rtc_time"

    sys_time_ts=$(date -d "$sys_time" +%s 2>/dev/null)
    new_rtc_time_ts=$(date -d "$new_rtc_time" +%s 2>/dev/null)

    if [ -z "$sys_time_ts" ] || [ -z "$new_rtc_time_ts" ]; then
        log "ERROR" "Failed to convert time format, cannot compare"
        return 5
    fi

    diff_sec=$((new_rtc_time_ts - sys_time_ts))
    if [ $diff_sec -ge 2 ] && [ $diff_sec -le 3 ]; then
        log "INFO" "RTC time is ticking normally (about 2 seconds), test passed"
        return 0
    else
        log "ERROR" "RTC time did not tick as expected (expected 2 seconds, actual: ${diff_sec} seconds), test failed"
        return 4
    fi
}

test_rtc