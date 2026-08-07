log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

test_spi_flash() {
    local rc_all=0
    # Only one SPI NOR exists on the hardware: U14 (BY25D40ESTIG, 4Mbit) on
    # SPI3_M2 CS0, see base board sheet 10. The second MTD device came from the
    # old device tree, which declared a flash on &spi1 with no matching part.
    local mtd_list=("/dev/mtdblock0")
    local idx=0

    for MTD_DEV in "${mtd_list[@]}"; do
        TEST_FILE="/tmp/mtd${idx}_test_data.bin"
        READ_FILE="/tmp/mtd${idx}_read_back.bin"
        TEST_SIZE=4096

        log "INFO" "==> SPI Flash (MTD${idx}) R/W self-test"

        if [ ! -e "$MTD_DEV" ]; then
            log "ERROR" "Device $MTD_DEV does not exist!"
            rc_all=1
            idx=$((idx+1))
            continue
        fi

        log "INFO" "Generating ${TEST_SIZE} bytes of random data..."
        dd if=/dev/urandom of="$TEST_FILE" bs=$TEST_SIZE count=1 2>/dev/null
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to generate test data!"
            rm -f "$TEST_FILE" "$READ_FILE"
            rc_all=2
            idx=$((idx+1))
            continue
        fi

        if command -v flash_erase >/dev/null 2>&1; then
            log "INFO" "flash_erase detected, erasing the first block..."
            flash_erase "$MTD_DEV" 0 1 >/dev/null 2>&1 || {
                log "ERROR" "Erase failed, write may fail."
            }
        else
            log "INFO" "flash_erase not detected, skipping erase step."
        fi

        log "INFO" "Writing test data to $MTD_DEV ..."
        dd if="$TEST_FILE" of="$MTD_DEV" bs=$TEST_SIZE count=1 2>/dev/null
        if [ $? -ne 0 ]; then
            log "ERROR" "Write failed!"
            rm -f "$TEST_FILE" "$READ_FILE"
            rc_all=3
            idx=$((idx+1))
            continue
        fi
        sync

        log "INFO" "Reading back ${TEST_SIZE} bytes from $MTD_DEV..."
        dd if="$MTD_DEV" of="$READ_FILE" bs=$TEST_SIZE count=1 2>/dev/null
        if [ $? -ne 0 ]; then
            log "ERROR" "Read failed!"
            rm -f "$TEST_FILE" "$READ_FILE"
            rc_all=4
            idx=$((idx+1))
            continue
        fi

        log "INFO" "Comparing written and read content..."
        if cmp -s "$TEST_FILE" "$READ_FILE"; then
            log "INFO" "Data matches, test passed for $MTD_DEV"
        else
            log "ERROR" "Data mismatch, test failed for $MTD_DEV"
            rc_all=5
        fi

        rm -f "$TEST_FILE" "$READ_FILE"
        idx=$((idx+1))
    done

    return $rc_all
}

test_spi_flash
