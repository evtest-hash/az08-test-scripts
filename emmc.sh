#!/bin/bash

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

TEST_FILE="/test_data.bin"
DATA_SIZE_MB=64
BLOCK_SIZE=1M

log INFO "Generating ${DATA_SIZE_MB}MB random data..."
dd if=/dev/urandom of=/tmp/test_data_src.bin bs=$BLOCK_SIZE count=$DATA_SIZE_MB status=progress
if [ $? -ne 0 ]; then
    log ERROR "Failed to generate random data"
    exit 1
fi

log INFO "Writing data to $TEST_FILE..."
dd if=/tmp/test_data_src.bin of=$TEST_FILE bs=$BLOCK_SIZE status=progress conv=fsync
if [ $? -ne 0 ]; then
    log ERROR "Failed to write data"
    rm -f /tmp/test_data_src.bin
    exit 1
fi

log INFO "Syncing disk cache..."
sync

log INFO "Dropping page cache to measure real eMMC speed..."
echo 3 > /proc/sys/vm/drop_caches

log INFO "Testing read speed..."
READ_SPEED=$(dd if=$TEST_FILE of=/dev/null bs=$BLOCK_SIZE iflag=direct status=progress 2>&1 | grep copied | awk '{print $(NF-1), $NF}')
log INFO "Read speed: $READ_SPEED"

log INFO "Dropping page cache for verification read..."
echo 3 > /proc/sys/vm/drop_caches

log INFO "Reading and verifying data..."
dd if=$TEST_FILE of=/tmp/test_data_read.bin bs=$BLOCK_SIZE status=progress
if [ $? -ne 0 ]; then
    log ERROR "Failed to read data"
    rm -f /tmp/test_data_src.bin /tmp/test_data_read.bin $TEST_FILE
    exit 1
fi

cmp /tmp/test_data_src.bin /tmp/test_data_read.bin
if [ $? -ne 0 ]; then
    log ERROR "Data verification failed"
    rm -f /tmp/test_data_src.bin /tmp/test_data_read.bin $TEST_FILE
    exit 1
fi
log INFO "Data verification passed"

log INFO "Deleting test files..."
rm -f $TEST_FILE /tmp/test_data_src.bin /tmp/test_data_read.bin

log INFO "eMMC test completed"

exit 0
