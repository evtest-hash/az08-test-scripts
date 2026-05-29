xlog() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

# Detect and mount SD card partition
mount_sdcard_partition() {
    SD_DEV="/dev/mmcblk1"
    MOUNT_POINT="/mnt/sdcard"

    # Check if device exists
    if [ ! -b "$SD_DEV" ]; then
        xlog "ERROR" "SD card device $SD_DEV does not exist!"
        return 1
    fi

    # Check partition (assume first partition is /dev/mmcblk1p1)
    PARTITION="${SD_DEV}p1"
    if [ ! -b "$PARTITION" ]; then
        xlog "ERROR" "SD card partition $PARTITION does not exist!"
        return 2
    fi

    # Create mount point if not exists
    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir -p "$MOUNT_POINT"
    fi

    # Check if already mounted
    mountpoint -q "$MOUNT_POINT"
    if [ $? -eq 0 ]; then
        xlog "INFO" "$PARTITION is already mounted at $MOUNT_POINT"
        return 0
    fi

    # Try to mount
    mount "$PARTITION" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        xlog "ERROR" "Failed to mount $PARTITION to $MOUNT_POINT!"
        return 3
    fi

    xlog "INFO" "Successfully mounted $PARTITION to $MOUNT_POINT"
    return 0
}

test_sd_card_rw() {
    SD_DEV="/dev/mmcblk1"
    PARTITION="${SD_DEV}p1"
    MOUNT_POINT="/mnt/sdcard"
    TEST_FILE="/tmp/sdcard_test_data.bin"
    READ_FILE="/tmp/sdcard_read_back.bin"
    TEST_SIZE=4096

    xlog "INFO" "==> SD card partition detection and mount"
    mount_sdcard_partition
    if [ $? -ne 0 ]; then
        xlog "ERROR" "SD card partition mount failed, aborting test"
        return 10
    fi

    # Check if mount point is writable
    if [ ! -w "$MOUNT_POINT" ]; then
        xlog "ERROR" "Mount point $MOUNT_POINT is not writable!"
        return 11
    fi

    xlog "INFO" "Generating ${TEST_SIZE} bytes of random data..."
    dd if=/dev/urandom of="$TEST_FILE" bs=$TEST_SIZE count=1 2>/dev/null
    if [ $? -ne 0 ]; then
        xlog "ERROR" "Failed to generate test data!"
        rm -f "$TEST_FILE" "$READ_FILE"
        return 2
    fi

    xlog "INFO" "Writing test data to SD card partition..."
    cp "$TEST_FILE" "$MOUNT_POINT/sdcard_test_data.bin"
    sync
    if [ $? -ne 0 ]; then
        xlog "ERROR" "Write failed!"
        rm -f "$TEST_FILE" "$READ_FILE"
        return 3
    fi

    xlog "INFO" "Reading back data from SD card partition..."
    cp "$MOUNT_POINT/sdcard_test_data.bin" "$READ_FILE"
    if [ $? -ne 0 ]; then
        xlog "ERROR" "Read failed!"
        rm -f "$TEST_FILE" "$READ_FILE" "$MOUNT_POINT/sdcard_test_data.bin"
        return 4
    fi

    xlog "INFO" "Comparing written and read content..."
    if cmp -s "$TEST_FILE" "$READ_FILE"; then
        xlog "INFO" "Data matches, test passed"
        rc=0
    else
        xlog "ERROR" "Data mismatch, test failed"
        rc=5
    fi

    rm -f "$TEST_FILE" "$READ_FILE" "$MOUNT_POINT/sdcard_test_data.bin"
    return $rc
}

test_sd_card_rw
