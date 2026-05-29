log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

test_keys() {
    local TIMEOUT=10
    local result=0

    log "INFO" "==> Key test..."

    log "INFO" "Please press the power key (PWRKEY) within ${TIMEOUT} seconds..."
    pwrkey_pass=1
    pwr_keys_path=$(find /sys/class/input -name "event*" -exec sh -c 'if [ "$(cat {}/device/name 2>/dev/null)" = "rk805 pwrkey" ]; then echo "{}"|sed "s,/sys/class/input,/dev/input,"; fi' \;)
    if [ -z "$pwr_keys_path" ]; then
        log "ERROR" "rk805 pwrkey device not found"
        pwrkey_pass=1
    else
        pwrkey_pressed=0
        timeout ${TIMEOUT}s evtest --grab $pwr_keys_path 2>/dev/null | while read line; do
            if echo "$line" | grep -q "type 1 (EV_KEY),"; then
                key=$(echo "$line" | grep -o "code [0-9]*" | cut -d " " -f 2)
                pkill evtest
                pwrkey_pressed=1
                exit 1
            fi
        done
        if [ $? -eq 1 ]; then
            log "INFO" "PWRKEY press detected, test passed"
            pwrkey_pass=0
        else
            log "ERROR" "PWRKEY press not detected, test failed"
            pwrkey_pass=1
        fi
    fi


    log "INFO" "Please press the BOOT key within ${TIMEOUT} seconds..."
    bootkey_pass=1
    bootkey_event_path=$(find /sys/class/input -name "event*" -exec sh -c 'if [ "$(cat {}/device/name 2>/dev/null)" = "boot-key" ]; then echo "{}"|sed "s,/sys/class/input,/dev/input,"; fi' \;)
    if [ -z "$bootkey_event_path" ]; then
        log "ERROR" "boot-key device not found"
        bootkey_pass=1
    else
        bootkey_pressed=0
        timeout ${TIMEOUT}s evtest --grab $bootkey_event_path 2>/dev/null | while read line; do
            if echo "$line" | grep -q "type 1 (EV_KEY),"; then
                key=$(echo "$line" | grep -o "code [0-9]*" | cut -d " " -f 2)
                pkill evtest
                bootkey_pressed=1
                exit 1
            fi
        done
        if [ $? -eq 1 ]; then
            log "INFO" "BOOTKEY press detected, test passed"
            bootkey_pass=0
        else
            log "ERROR" "BOOTKEY press not detected, test failed"
            bootkey_pass=1
        fi
    fi

    log "INFO" "Please press the RECOVERY key within ${TIMEOUT} seconds..."
    recoverykey_pass=1
    recoverykey_event_path=$(find /sys/class/input -name "event*" -exec sh -c 'if [ "$(cat {}/device/name 2>/dev/null)" = "recovery-key" ]; then echo "{}"|sed "s,/sys/class/input,/dev/input,"; fi' \;)
    if [ -z "$recoverykey_event_path" ]; then
        log "ERROR" "recovery-key device not found"
        recoverykey_pass=1
    else
        recoverykey_pressed=0
        timeout ${TIMEOUT}s evtest --grab $recoverykey_event_path 2>/dev/null | while read line; do
            if echo "$line" | grep -q "type 1 (EV_KEY),"; then
                key=$(echo "$line" | grep -o "code [0-9]*" | cut -d " " -f 2)
                pkill evtest
                recoverykey_pressed=1
                exit 1
            fi
        done
        if [ $? -eq 1 ]; then
            log "INFO" "RECOVERYKEY press detected, test passed"
            recoverykey_pass=0
        else
            log "ERROR" "RECOVERYKEY press not detected, test failed"
            recoverykey_pass=1
        fi
    fi

    if [ $pwrkey_pass -eq 0 ] && [ $bootkey_pass -eq 0 ] && [ $recoverykey_pass -eq 0 ]; then
        result=0
    else
        result=1
    fi
    return $result
}

test_keys
