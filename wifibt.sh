log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

test_bluetooth_wifi() {
    log "INFO" "==> Checking WiFi and Bluetooth..."
    killall ipc-daemon netserver connmand wpa_supplicant 2>/dev/null

    wifi=$(ifconfig -a | grep "wlan0")
    if [ -z "$wifi" ]; then
        log "ERROR" "WiFi device wlan0 not detected"
        return 1
    fi

    log "INFO" "Scanning for WiFi hotspots..."
    # Retry with a wlan0 reset in between: killing wpa_supplicant mid-scan can
    # wedge the driver's WEXT scan path (iwlist then returns empty instantly and
    # stays that way for 30s+); a down/up cycle clears it deterministically.
    scan_attempts=3
    attempt=1
    while :; do
        wifi_scan=$(iwlist wlan0 scanning | grep "ESSID")
        wifi_count=$(echo "$wifi_scan" | grep -v "^\s*$" | wc -l)
        if [ "$wifi_count" -gt 0 ] || [ "$attempt" -ge "$scan_attempts" ]; then
            break
        fi
        log "WARN" "WiFi scan attempt $attempt/$scan_attempts found nothing, resetting wlan0 and retrying..."
        attempt=$((attempt + 1))
        ifconfig wlan0 down
        sleep 1
        ifconfig wlan0 up
        sleep 1
    done
    if [ "$wifi_count" -eq 0 ]; then
        log "ERROR" "No WiFi hotspots found"
        return 1
    else
        log "INFO" "Found $wifi_count WiFi hotspots"
        log "INFO" "WiFi Hotspot List:"
        echo "$wifi_scan" | sed -n 's/.*ESSID:"\(.*\)"/\1/p' | while read essid; do
            if [ -n "$essid" ]; then
                log "INFO" "  - $essid"
            fi
        done
    fi

    if [ ! -e /sys/class/bluetooth/hci0 ] && ! hciconfig hci0 >/dev/null 2>&1; then
        log "ERROR" "Bluetooth device hci0 not detected"
        return 1
    fi

    log "INFO" "Scanning for Bluetooth LE devices (5 seconds)..."
    # Start LE scan in background, kill after 5 seconds, collect output
    le_scan_file=$(mktemp)
    hcitool lescan > "$le_scan_file" 2>/dev/null &
    le_scan_pid=$!
    sleep 5
    kill -2 "$le_scan_pid" 2>/dev/null
    wait "$le_scan_pid" 2>/dev/null

    # Remove the first line ("LE Scan ...") and empty lines, deduplicate
    le_devices=$(sed '1d' "$le_scan_file" | grep -v "^\s*$" | sort | uniq)
    rm -f "$le_scan_file"
    le_count=$(echo "$le_devices" | grep -v "^\s*$" | wc -l)
    if [ "$le_count" -eq 0 ]; then
        log "ERROR" "No Bluetooth LE devices found"
        return 1
    else
        log "INFO" "Found $le_count Bluetooth LE devices"
        log "INFO" "Bluetooth LE Device List:"
        echo "$le_devices" | while read line; do
            if [ -n "$line" ]; then
                log "INFO" "  - $line"
            fi
        done
    fi

    log "INFO" "WiFi and Bluetooth check completed, devices are working"
    return 0
}

test_bluetooth_wifi
