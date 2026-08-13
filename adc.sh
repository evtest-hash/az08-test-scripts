#!/bin/bash
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

# Find IIO ADC device with the specified channels
find_adc_dev() {
    local ch1="$1" ch2="$2" d
    for d in /sys/bus/iio/devices/iio:device*; do
        if [ -f "$d/in_voltage${ch1}_raw" ] && [ -f "$d/in_voltage${ch2}_raw" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

# ---- SARADC resistor ladder (core board sheet 22) ----------------------------
#
# Every ID/config strap on the core board uses the same divider ladder off
# VCCA1V8_PLDO2_S0. Rup is 10K for every level except index 0 (Rup = NC, so the
# node is pulled to GND) and index 10 (Rdown = NC, so it is pulled to VREF).
#
#   idx  Rup / Rdown     ADC
#   ---  -------------   ----
#    0   NC   / 10K         0
#    1   10K  / 1.13K     416
#    2   10K  / 2.49K     816
#    3   10K  / 4.3K     1231
#    4   10K  / 6.8K     1658
#    5   10K  / 10K      2048
#    6   10K  / 14.7K    2437
#    7   10K  / 23.2K    2862
#    8   10K  / 40.2K    3279
#    9   10K  / 88.7K    3680
#   10   10K  / NC       4095
#
# The readings are ratiometric: the top of every divider and the ADC reference
# are the same rail (VCCA1V8_PLDO2_S0 feeds SARADC_AVDD1V8, ball 2A10), so
#     code = 4096 * Rdown / (Rup + Rdown)
# and the absolute accuracy of the 1.8V rail drops out of the error budget.
#
# Error budget, in ADC counts:
#   resistor tolerance (both +-1%, worst case opposing)  +-20  (max at k=0.5)
#   SARADC INL/DNL + offset                              +-30
#   noise (SAMPLES averaging, 1nF on the input)          +-10
#   divider source impedance x ADC input leakage         +-20
#   -> linear sum +-80, RSS +-42
#
# The smallest gap between adjacent levels is 389 counts (2048 -> 2437), so the
# accept window cannot exceed 389/2 = 194. LADDER_TOL=150 is 3.6x the RSS budget
# and still rejects a wrong strap resistor (>=389 off, i.e. >=239 outside the
# window). LADDER_WARN flags readings that decode cleanly but sit further from
# nominal than expected -- collect the real spread on the line before tightening
# LADDER_TOL, rather than guessing.
#
# NOTE: idx 0 is "Rup = NC" and idx 10 is "Rdown = NC", so an unfitted resistor
# decodes as a legitimate level rather than a fault. No tolerance can catch
# that; the module ID cross-check covers part of it, HW_ID has nothing to
# cross-check against.
LADDER="0 416 816 1231 1658 2048 2437 2862 3279 3680 4095"
LADDER_LEVELS=11
LADDER_TOL="${LADDER_TOL:-150}"
LADDER_WARN="${LADDER_WARN:-100}"
SAMPLES="${SAMPLES:-3}"

# Module IDs that are on sheet 22 but whose Customer P/N is UNDEFINED pass with
# a WARN: SKUs get confirmed ad hoc and the factory-test firmware may lag, so
# failing them would break the line for a legitimate board. IDs that are not on
# the sheet at all (37..121) are a FAIL by default -- that is a wrong strap or
# an unknown build, not a firmware-lag problem. Set to 1 to let those through.
ALLOW_UNKNOWN_MODULE_ID="${ALLOW_UNKNOWN_MODULE_ID:-0}"

# ladder_index <raw> ; echoes "<idx> <nominal> <deviation>", or returns 1 if the
# reading is not within LADDER_TOL of any level
ladder_index() {
    awk -v raw="$1" -v tol="$LADDER_TOL" -v ladder="$LADDER" '
        BEGIN {
            n = split(ladder, L, " ")
            best = -1; bestd = 1e9
            for (i = 1; i <= n; i++) {
                d = raw - L[i]; if (d < 0) d = -d
                if (d < bestd) { bestd = d; best = i - 1 }
            }
            if (bestd > tol) exit 1
            printf "%d %d %.1f\n", best, L[best + 1], bestd
        }'
}

# report_ladder <label> <idx> <nominal> <deviation>
report_ladder() {
    log "INFO" "$1: idx=$2 nominal=$3 deviation=$4 counts (tol=+-${LADDER_TOL})"
    if awk -v d="$4" -v w="$LADDER_WARN" 'BEGIN{ exit !(d > w) }'; then
        log "WARN" "$1: deviation $4 exceeds ${LADDER_WARN} counts -- decodes cleanly but is marginal, worth tracking"
    fi
}

# adc_sample <dev> <channel> <samples> ; echoes "n avg min max"
adc_sample() {
    local dev="$1" ch="$2" samples="$3"
    {
        local i=0 v
        while [ "$i" -lt "$samples" ]; do
            v="$(cat "${dev}/in_voltage${ch}_raw" 2>/dev/null || echo "")"
            echo "$v" | grep -qE '^[0-9]+$' && echo "$v"
            i=$((i + 1))
            usleep 50000 2>/dev/null || sleep 0.05
        done
    } | awk '
        BEGIN { min = 1e9; max = -1 }
        NF { v = $1 + 0; n++; sum += v; if (v < min) min = v; if (v > max) max = v }
        END {
            if (n == 0) { print "0 0 0 0"; exit }
            printf "%d %.2f %d %d\n", n, sum / n, min, max
        }'
}

check_samples() {
    if ! echo "$SAMPLES" | grep -qE '^[0-9]+$' || [ "$SAMPLES" -le 0 ]; then
        log "ERROR" "SAMPLES must be a positive integer"
        return 1
    fi
    return 0
}

test_adc_voltage() {
    log "INFO" "==> ADC voltage test (channel 3, 4, 5)"

    local adc_dev
    adc_dev="$(find_adc_dev 3 5 || true)"
    if [ -z "$adc_dev" ]; then
        log "ERROR" "No IIO ADC node with voltage3~5 found"
        return 1
    fi

    local scale
    scale=$(cat "$adc_dev/in_voltage_scale")
    local all_passed=1

    for channel in 3 4 5; do
        local raw_value voltage_mv min max threshold
        raw_value=$(cat "$adc_dev/in_voltage${channel}_raw")
        voltage_mv=$(awk "BEGIN { printf \"%.3f\", $raw_value * $scale }")

        case $channel in
            3)
                min=750; max=1250
                if ! awk "BEGIN { exit ($voltage_mv >= $min && $voltage_mv <= $max) ? 0 : 1 }"; then
                    log "ERROR" "Channel 3: $voltage_mv mV NOT in $min-$max mV"
                    all_passed=0
                else
                    log "INFO" "Channel 3: $voltage_mv mV in $min-$max mV"
                fi
                ;;
            4)
                min=900; max=1200
                if ! awk "BEGIN { exit ($voltage_mv >= $min && $voltage_mv <= $max) ? 0 : 1 }"; then
                    log "ERROR" "Channel 4: $voltage_mv mV NOT in $min-$max mV"
                    all_passed=0
                else
                    log "INFO" "Channel 4: $voltage_mv mV in $min-$max mV"
                fi
                ;;
            5)
                threshold=1000
                if ! awk "BEGIN { exit ($voltage_mv < $threshold) ? 0 : 1 }"; then
                    log "ERROR" "Channel 5: $voltage_mv mV NOT < $threshold mV"
                    all_passed=0
                else
                    log "INFO" "Channel 5: $voltage_mv mV < $threshold mV"
                fi
                ;;
        esac
    done

    if [ $all_passed -eq 1 ]; then
        log "INFO" "ADC voltage test PASSED"
        return 0
    else
        log "ERROR" "ADC voltage test FAILED"
        return 1
    fi
}

# ---- core board revision (channel 2, SARADC_VIN2_HW_ID) ----------------------
#
# The HW_ID strap uses the same ladder and sheet 22 assigns all 11 levels.
# HW_ID number = idx + 1, but the VERSION column is NOT a formula: it runs
# V1.0.0..V1.9.0 and then rolls over to V2.0.0 at the last level, so it has to
# be a lookup.
#
#   sheet row   Rup / Rdown     ADC    VERSION   idx
#   ---------   -------------   ----   -------   ---
#   HW_ID1      NC   / 10K         0   V1.0.0     0
#   HW_ID2      10K  / 1.13K     416   V1.1.0     1
#   HW_ID3      10K  / 2.49K     816   V1.2.0     2
#   HW_ID4      10K  / 4.3K     1231   V1.3.0     3
#   HW_ID5      10K  / 6.8K     1658   V1.4.0     4
#   HW_ID6      10K  / 10K      2048   V1.5.0     5
#   HW_ID7      10K  / 14.7K    2437   V1.6.0     6
#   HW_ID8      10K  / 23.2K    2862   V1.7.0     7
#   HW_ID9      10K  / 40.2K    3279   V1.8.0     8
#   HW_ID10     10K  / 88.7K    3680   V1.9.0     9
#   HW_ID11     10K  / NC       4095   V2.0.0    10
HW_ID_VERSIONS="V1.0.0 V1.1.0 V1.2.0 V1.3.0 V1.4.0 V1.5.0 V1.6.0 V1.7.0 V1.8.0 V1.9.0 V2.0.0"
CORE_REV=""
CORE_HW_ID=""

test_core_rev() {
    log "INFO" "==> Core board revision (channel 2, SARADC_VIN2_HW_ID)"

    check_samples || return 1

    local adc_dev
    adc_dev="$(find_adc_dev 2 2 || true)"
    if [ -z "$adc_dev" ]; then
        log "ERROR" "No IIO ADC node with voltage2 found"
        return 1
    fi

    local n avg vmin vmax
    read -r n avg vmin vmax <<<"$(adc_sample "$adc_dev" 2 "$SAMPLES")"
    if [ "$n" -eq 0 ]; then
        log "ERROR" "No valid channel 2 sample"
        return 1
    fi
    log "INFO" "Channel 2 samples: n=$n avg=$avg range=[$vmin..$vmax]"

    local decoded idx nominal dev
    if ! decoded="$(ladder_index "$avg")"; then
        log "ERROR" "Channel 2 raw=$avg is not on the resistor ladder (tolerance +-${LADDER_TOL})"
        log "ERROR" "HW_ID strap resistor is wrong/unfitted, or the ADC input is faulty"
        return 1
    fi
    read -r idx nominal dev <<<"$decoded"
    report_ladder "Channel 2 (HW_ID)" "$idx" "$nominal" "$dev"

    CORE_HW_ID="HW_ID$((idx + 1))"
    CORE_REV="$(awk -v i="$idx" '{print $(i + 1)}' <<<"$HW_ID_VERSIONS")"
    if [ -z "$CORE_REV" ]; then
        log "ERROR" "${CORE_HW_ID} (idx=${idx}) has no version in HW_ID_VERSIONS"
        return 1
    fi
    log "INFO" "Decoded: ${CORE_HW_ID} => core board revision ${CORE_REV}"

    log "INFO" "Core board revision check PASSED (${CORE_HW_ID} / ${CORE_REV})"
    return 0
}

# ---- module ID (channel 6 + 7) ----------------------------------------------
#
# Layer 1 decodes both channels to ladder indices and computes the module ID
# arithmetically:
#
#     module_id = idx6 * 11 + idx7 + 1
#
# This covers all 121 grid points, including the ones sheet 22 has not assigned
# a SKU to yet (it currently defines ID1..ID36). Verified against every row of
# the sheet 22 table: ID1=(0,0) ID11=(0,4095) ID12=(416,0) ID13=(416,416)
# ID22=(416,4095) ID23=(816,0) ID33=(816,4095) ID34=(1231,0) ID36=(1231,816).
#
# Layer 2 carries all 36 rows of sheet 22 (rev V1.1.0). The pn field is either
# the confirmed Customer P/N or UNDEFINED: the hardware configuration of an
# UNDEFINED row IS defined on the sheet -- only the customer part number is not
# confirmed yet -- so the cross-check still runs, but the result is a WARN
# instead of a FAIL (see ALLOW_UNKNOWN_MODULE_ID note above). When a P/N gets
# confirmed, replace UNDEFINED with it and the row becomes strictly enforced.
#
# Format: id|pn|cpu|ddr_type|ddr_mb|emmc_gb|wifi|description
MODULE_SPEC=$(
cat <<'EOF'
1|INM-ICS-000633|RK3576S|LPDDR4X|2048|8|WITH|RK3576S LPDDR4X 2+8GB WITH WIFI+BT
2|INM-ICS-000632|RK3576S|LPDDR4X|2048|8|WITHOUT|RK3576S LPDDR4X 2+8GB WITHOUT WIFI+BT
3|UNDEFINED|RK3576|LPDDR4X|2048|8|WITH|RK3576 LPDDR4X 2+8GB WITH WIFI+BT
4|UNDEFINED|RK3576|LPDDR4X|2048|8|WITHOUT|RK3576 LPDDR4X 2+8GB WITHOUT WIFI+BT
5|INM-ICS-000633|RK3576S|LPDDR4|2048|8|WITH|RK3576S LPDDR4 2+8GB WITH WIFI+BT
6|INM-ICS-000632|RK3576S|LPDDR4|2048|8|WITHOUT|RK3576S LPDDR4 2+8GB WITHOUT WIFI+BT
7|UNDEFINED|RK3576|LPDDR4|2048|8|WITH|RK3576 LPDDR4 2+8GB WITH WIFI+BT
8|UNDEFINED|RK3576|LPDDR4|2048|8|WITHOUT|RK3576 LPDDR4 2+8GB WITHOUT WIFI+BT
9|INM-ICS-000633|RK3576S|LPDDR5|2048|8|WITH|RK3576S LPDDR5 2+8GB WITH WIFI+BT
10|INM-ICS-000632|RK3576S|LPDDR5|2048|8|WITHOUT|RK3576S LPDDR5 2+8GB WITHOUT WIFI+BT
11|UNDEFINED|RK3576|LPDDR5|2048|8|WITH|RK3576 LPDDR5 2+8GB WITH WIFI+BT
12|UNDEFINED|RK3576|LPDDR5|2048|8|WITHOUT|RK3576 LPDDR5 2+8GB WITHOUT WIFI+BT
13|INM-ICS-000633|RK3576S|LPDDR4X|2048|32|WITH|RK3576S LPDDR4X 2+32GB WITH WIFI+BT
14|UNDEFINED|RK3576S|LPDDR4X|2048|32|WITHOUT|RK3576S LPDDR4X 2+32GB WITHOUT WIFI+BT
15|UNDEFINED|RK3576|LPDDR4X|2048|32|WITH|RK3576 LPDDR4X 2+32GB WITH WIFI+BT
16|UNDEFINED|RK3576|LPDDR4X|2048|32|WITHOUT|RK3576 LPDDR4X 2+32GB WITHOUT WIFI+BT
17|INM-ICS-000633|RK3576S|LPDDR4|2048|32|WITH|RK3576S LPDDR4 2+32GB WITH WIFI+BT
18|UNDEFINED|RK3576S|LPDDR4|2048|32|WITHOUT|RK3576S LPDDR4 2+32GB WITHOUT WIFI+BT
19|UNDEFINED|RK3576|LPDDR4|2048|32|WITH|RK3576 LPDDR4 2+32GB WITH WIFI+BT
20|UNDEFINED|RK3576|LPDDR4|2048|32|WITHOUT|RK3576 LPDDR4 2+32GB WITHOUT WIFI+BT
21|INM-ICS-000633|RK3576S|LPDDR5|2048|32|WITH|RK3576S LPDDR5 2+32GB WITH WIFI+BT
22|UNDEFINED|RK3576S|LPDDR5|2048|32|WITHOUT|RK3576S LPDDR5 2+32GB WITHOUT WIFI+BT
23|UNDEFINED|RK3576|LPDDR5|2048|32|WITH|RK3576 LPDDR5 2+32GB WITH WIFI+BT
24|UNDEFINED|RK3576|LPDDR5|2048|32|WITHOUT|RK3576 LPDDR5 2+32GB WITHOUT WIFI+BT
25|INM-ICS-000649|RK3576S|LPDDR4X|4096|64|WITH|RK3576S LPDDR4X 4+64GB WITH WIFI+BT
26|UNDEFINED|RK3576S|LPDDR4X|4096|64|WITHOUT|RK3576S LPDDR4X 4+64GB WITHOUT WIFI+BT
27|UNDEFINED|RK3576|LPDDR4X|4096|64|WITH|RK3576 LPDDR4X 4+64GB WITH WIFI+BT
28|UNDEFINED|RK3576|LPDDR4X|4096|64|WITHOUT|RK3576 LPDDR4X 4+64GB WITHOUT WIFI+BT
29|INM-ICS-000649|RK3576S|LPDDR4|4096|64|WITH|RK3576S LPDDR4 4+64GB WITH WIFI+BT
30|UNDEFINED|RK3576S|LPDDR4|4096|64|WITHOUT|RK3576S LPDDR4 4+64GB WITHOUT WIFI+BT
31|UNDEFINED|RK3576|LPDDR4|4096|64|WITH|RK3576 LPDDR4 4+64GB WITH WIFI+BT
32|UNDEFINED|RK3576|LPDDR4|4096|64|WITHOUT|RK3576 LPDDR4 4+64GB WITHOUT WIFI+BT
33|INM-ICS-000649|RK3576S|LPDDR5|4096|64|WITH|RK3576S LPDDR5 4+64GB WITH WIFI+BT
34|UNDEFINED|RK3576S|LPDDR5|4096|64|WITHOUT|RK3576S LPDDR5 4+64GB WITHOUT WIFI+BT
35|UNDEFINED|RK3576|LPDDR5|4096|64|WITH|RK3576 LPDDR5 4+64GB WITH WIFI+BT
36|UNDEFINED|RK3576|LPDDR5|4096|64|WITHOUT|RK3576 LPDDR5 4+64GB WITHOUT WIFI+BT
EOF
)

# Measured hardware, filled in by read_hw_actual()
HW_CPU="UNKNOWN" HW_CPU_BIN="N/A" HW_OTP=""
HW_DDR_TYPE="" HW_DDR_MB=0
HW_EMMC_GIB=0 HW_EMMC_NAME=""
HW_WIFI_PRESENT=0 HW_WIFI_INFO=""

read_hw_actual() {
    # CPU from OTP byte 8
    local otp_hex=""
    if [ -r /sys/bus/nvmem/devices/rockchip-otp0/nvmem ]; then
        if command -v hexdump >/dev/null 2>&1; then
            otp_hex="$(hexdump -s 8 -n 1 -e '1/1 "0x%02x"' /sys/bus/nvmem/devices/rockchip-otp0/nvmem 2>/dev/null || true)"
        fi
        if [ -z "$otp_hex" ]; then
            otp_hex="$(dd if=/sys/bus/nvmem/devices/rockchip-otp0/nvmem bs=1 skip=8 count=1 2>/dev/null | od -An -tx1 | awk 'NR==1{print "0x"$1}' || true)"
        fi
    fi
    HW_OTP="$(echo "${otp_hex}" | tr 'A-Z' 'a-z' | awk 'NR==1{print $1}')"
    case "${HW_OTP}" in
        0x01) HW_CPU="RK3576";  HW_CPU_BIN="0" ;;
        0x13) HW_CPU="RK3576S"; HW_CPU_BIN="3" ;;
        0x0a) HW_CPU="RK3576J"; HW_CPU_BIN="2" ;;
        0x0d) HW_CPU="RK3576M"; HW_CPU_BIN="1" ;;
    esac
    log "INFO" "CPU:  OTP byte8=${HW_OTP:-N/A} bin=${HW_CPU_BIN} => ${HW_CPU}"

    # DDR
    local dmcinfo
    dmcinfo="$(cat /proc/dmcdbg/dmcinfo 2>/dev/null || true)"
    HW_DDR_TYPE="$(awk -F': *' '/^DramType:/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit}' <<<"${dmcinfo}")"
    HW_DDR_MB="$(awk -F': *' '/^TotalSize:/ {sum += ($2+0)} END {print sum+0}' <<<"${dmcinfo}")"
    log "INFO" "DDR:  type=${HW_DDR_TYPE:-N/A} capacity=${HW_DDR_MB:-0}MB"

    # eMMC
    local emmc_sectors emmc_lba
    emmc_sectors="$(awk 'NR==1{print $1+0}' /sys/block/mmcblk0/size 2>/dev/null || echo 0)"
    emmc_lba="$(awk 'NR==1{print $1+0}' /sys/block/mmcblk0/queue/logical_block_size 2>/dev/null || echo 512)"
    [ "$emmc_lba" -gt 0 ] 2>/dev/null || emmc_lba=512
    HW_EMMC_GIB="$(awk -v s="${emmc_sectors}" -v b="${emmc_lba}" 'BEGIN{printf "%.2f", (s*b)/(1024*1024*1024)}')"
    HW_EMMC_NAME="$(cat /sys/bus/mmc/devices/mmc0:0001/name 2>/dev/null | awk 'NR==1{print $0}')"
    log "INFO" "eMMC: ${HW_EMMC_GIB}GiB name=${HW_EMMC_NAME:-N/A}"

    # WiFi / BT
    local sdio_count wlan_count bcmdhd_count
    sdio_count="$(find /sys/bus/sdio/devices -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | awk '{print $1+0}')"
    if [ -x /usr/bin/wifibt-util.sh ]; then
        HW_WIFI_INFO="$(/usr/bin/wifibt-util.sh info 2>/dev/null || true)"
    fi
    if command -v ip >/dev/null 2>&1; then
        wlan_count="$(ip -o link show 2>/dev/null | awk -F': ' '/wlan/{n++} END{print n+0}')"
    else
        wlan_count="$(find /sys/class/net -maxdepth 1 -name 'wlan*' 2>/dev/null | wc -l | awk '{print $1+0}')"
    fi
    if command -v lsmod >/dev/null 2>&1; then
        bcmdhd_count="$(lsmod 2>/dev/null | awk '/^bcmdhd /{n++} END{print n+0}')"
    else
        bcmdhd_count=0
    fi
    HW_WIFI_PRESENT=0
    if [ "$sdio_count" -gt 0 ] || [ -n "$HW_WIFI_INFO" ] || [ "$wlan_count" -gt 0 ] || [ "$bcmdhd_count" -gt 0 ]; then
        HW_WIFI_PRESENT=1
    fi
    log "INFO" "WiFi: present=${HW_WIFI_PRESENT} sdio=$sdio_count wlan=$wlan_count bcmdhd=$bcmdhd_count info='${HW_WIFI_INFO}'"
}

validate_against_spec() {
    local exp_cpu="$1" exp_ddr_type="$2" exp_ddr_mb="$3" exp_emmc_gb="$4" exp_wifi="$5"
    local pass_cpu="FAIL" pass_ddr_type="FAIL" pass_ddr_mb="FAIL" pass_emmc="FAIL" pass_wifi="FAIL"

    [ "$HW_CPU" = "$exp_cpu" ] && pass_cpu="PASS"
    log "INFO" "[CPU]   expect=$exp_cpu actual=$HW_CPU => $pass_cpu"

    local a b
    a="$(echo "${HW_DDR_TYPE}" | tr '[:lower:]' '[:upper:]')"
    b="$(echo "${exp_ddr_type}" | tr '[:lower:]' '[:upper:]')"
    [ -n "${HW_DDR_TYPE}" ] && [ "$a" = "$b" ] && pass_ddr_type="PASS"

    if [ -n "${HW_DDR_MB}" ] && [ "${HW_DDR_MB}" -gt 0 ] 2>/dev/null; then
        if [ "${HW_DDR_MB}" -ge $((exp_ddr_mb - 128)) ] && [ "${HW_DDR_MB}" -le $((exp_ddr_mb + 128)) ]; then
            pass_ddr_mb="PASS"
        fi
    fi
    log "INFO" "[DDR]   expect=$exp_ddr_type/${exp_ddr_mb}MB actual=${HW_DDR_TYPE:-N/A}/${HW_DDR_MB:-0}MB => type:$pass_ddr_type cap:$pass_ddr_mb"

    # eMMC user area is always smaller than the nominal density: JEDEC defines no
    # nominal-density field at all (the part only reports SEC_COUNT), and vendors
    # subtract boot/RPMB partitions plus management area from it. The shortfall is
    # proportional, not fixed, and it differs per vendor:
    #
    #   Samsung Table 18   64GB -> 62,537,072,640 B = 58.24GiB   0.977 of nominal
    #   Flexxon Ind 5.1     8GB ->  7,834,959,872 B =  7.30GiB   0.979
    #   Micron MTFC8GAKAJCN 8GB ->                     7.09GiB   0.952
    #   Gateworks floor    64GB -> 61,203,283,968 B = 57.00GiB   0.956
    #
    # So a fixed +-GiB window cannot work: it must be wide enough for 0.952 yet
    # the shortfall doubles with every capacity tier. Compare by ratio instead.
    #
    # Bound at /*sqrt(2) -- the geometric midpoint between adjacent capacity tiers.
    # This is AOSP roundStorageSize's ladder, but centred on the tier instead of
    # sitting at its top edge, so the margin is balanced on both sides:
    #
    #   real material  0.952..0.979  ->  1.346x above the 0.7071 bound   (no false FAIL)
    #   32GB mis-stuff 0.489..0.537  ->  1.32x  below it                 (no missed FAIL)
    #
    # The 32GB figure allows for a part exposing its full *binary* 32GiB (0.537),
    # which AOSP's top-edge window would misread as the next tier up. 128GB
    # mis-stuff lands at 1.90 and a missing/unenumerated eMMC reads 0.00; both
    # fall outside. Second-source material passes on capacity alone -- no vendor
    # table to keep in sync, so new material cannot stop the line.
    #
    # PRECONDITION on sqrt(2): it is the midpoint for tiers 2x apart. A mis-stuffed
    # density S is only rejected reliably when S/expected is outside 0.722..1.486
    # (0.7071/0.9794 and 1.4142/0.9516). Every eMMC density is a power of two, so
    # neighbours sit at 0.5x / 2.0x and clear that band easily -- but this holds
    # only while MODULE_SPEC stays on the power-of-two ladder. Adding a density
    # such as 48GB alongside 64GB (0.75x) would be silently accepted here; that
    # pair needs sqrt(48/64)=1.155, which leaves only 1.10x over real material,
    # i.e. capacity can no longer identify the part and CID/PNM must do it.
    # Capacities currently in MODULE_SPEC: 8 / 32 / 64 -- all powers of two.
    local emmc_exp_gib
    emmc_exp_gib="$(awk -v g="${exp_emmc_gb}" 'BEGIN{printf "%.2f", (g*1000*1000*1000)/(1024*1024*1024)}')"
    if awk -v real="${HW_EMMC_GIB}" -v tgt="${emmc_exp_gib}" \
        'BEGIN{ exit !(tgt > 0 && real > tgt/1.4142 && real <= tgt*1.4142) }'; then
        pass_emmc="PASS"
    fi
    log "INFO" "[eMMC]  expect=${exp_emmc_gb}GB(~${emmc_exp_gib}GiB) actual=${HW_EMMC_GIB}GiB name=${HW_EMMC_NAME:-N/A} => $pass_emmc"

    if [ "${exp_wifi}" = "WITHOUT" ]; then
        [ "$HW_WIFI_PRESENT" -eq 0 ] && pass_wifi="PASS"
    else
        [ "$HW_WIFI_PRESENT" -eq 1 ] && pass_wifi="PASS"
    fi
    log "INFO" "[WiFi]  expect=$exp_wifi actual=$( [ "$HW_WIFI_PRESENT" -eq 1 ] && echo WITH || echo WITHOUT ) => $pass_wifi"

    if [ "$pass_cpu" = "PASS" ] && [ "$pass_ddr_type" = "PASS" ] && \
       [ "$pass_ddr_mb" = "PASS" ] && [ "$pass_emmc" = "PASS" ] && [ "$pass_wifi" = "PASS" ]; then
        return 0
    fi
    return 1
}

test_hwcfg() {
    log "INFO" "==> Module ID / hardware configuration check (channel 6, 7)"

    check_samples || return 1

    local adc_dev
    adc_dev="$(find_adc_dev 6 7 || true)"
    if [ -z "$adc_dev" ]; then
        log "ERROR" "No IIO ADC node with voltage6~7 found"
        return 1
    fi

    local n6 avg6 min6 max6 n7 avg7 min7 max7
    read -r n6 avg6 min6 max6 <<<"$(adc_sample "$adc_dev" 6 "$SAMPLES")"
    read -r n7 avg7 min7 max7 <<<"$(adc_sample "$adc_dev" 7 "$SAMPLES")"
    if [ "$n6" -eq 0 ] || [ "$n7" -eq 0 ]; then
        log "ERROR" "No valid channel 6/7 sample"
        return 1
    fi
    log "INFO" "Channel 6: n=$n6 avg=$avg6 range=[$min6..$max6]"
    log "INFO" "Channel 7: n=$n7 avg=$avg7 range=[$min7..$max7]"

    # ---- layer 1: ladder decode -> module ID (never needs the spec table) ----
    local d6 d7 idx6 nom6 dev6 idx7 nom7 dev7 module_id
    if ! d6="$(ladder_index "$avg6")"; then
        log "ERROR" "Channel 6 raw=$avg6 is not on the resistor ladder (tolerance +-${LADDER_TOL})"
        log "ERROR" "Module ID strap resistor is wrong/unfitted, or the ADC input is faulty"
        return 1
    fi
    if ! d7="$(ladder_index "$avg7")"; then
        log "ERROR" "Channel 7 raw=$avg7 is not on the resistor ladder (tolerance +-${LADDER_TOL})"
        log "ERROR" "Module ID strap resistor is wrong/unfitted, or the ADC input is faulty"
        return 1
    fi
    read -r idx6 nom6 dev6 <<<"$d6"
    read -r idx7 nom7 dev7 <<<"$d7"
    report_ladder "Channel 6 (MODULE_ID hi)" "$idx6" "$nom6" "$dev6"
    report_ladder "Channel 7 (MODULE_ID lo)" "$idx7" "$nom7" "$dev7"

    # Sheet 22 numbers the rows CONF_ID1..CONF_ID36, i.e. 1-based
    module_id=$(( idx6 * LADDER_LEVELS + idx7 + 1 ))
    log "INFO" "Decoded: ch6 idx=${idx6} ch7 idx=${idx7} => CONF_ID${module_id}"

    # ---- layer 2: spec lookup ------------------------------------------------
    local spec exp_pn exp_cpu exp_ddr_type exp_ddr_mb exp_emmc_gb exp_wifi exp_text
    spec="$(awk -F'|' -v id="$module_id" '$1 == id { print; exit }' <<<"${MODULE_SPEC}")"

    read_hw_actual

    if [ -z "$spec" ]; then
        log "WARN" "MODULE_ID=${module_id} is not on sheet 22 (only ID1..ID36 are defined)"
        log "WARN" "The strap itself decoded cleanly, so this is either a wrong strap combination or a build this firmware does not know."
        log "WARN" "Measured inventory: CPU=${HW_CPU} DDR=${HW_DDR_TYPE:-N/A}/${HW_DDR_MB}MB" \
                   "eMMC=${HW_EMMC_GIB}GiB WiFi=$( [ "$HW_WIFI_PRESENT" -eq 1 ] && echo WITH || echo WITHOUT )"
        if [ "$ALLOW_UNKNOWN_MODULE_ID" = "1" ]; then
            log "WARN" "ALLOW_UNKNOWN_MODULE_ID=1, reporting only -- no cross-check performed"
            log "INFO" "Module ID check PASSED (unverified, MODULE_ID=${module_id})"
            return 0
        fi
        log "ERROR" "Update MODULE_SPEC from the latest sheet 22, or set ALLOW_UNKNOWN_MODULE_ID=1"
        log "ERROR" "Module ID check FAILED (unknown MODULE_ID=${module_id})"
        return 1
    fi

    IFS='|' read -r _ exp_pn exp_cpu exp_ddr_type exp_ddr_mb exp_emmc_gb exp_wifi exp_text <<<"${spec}"
    log "INFO" "MODULE_ID=${module_id} => ${exp_text} (P/N: ${exp_pn})"

    if [ "$exp_pn" = "UNDEFINED" ]; then
        # SKU exists on the sheet but the Customer P/N is not confirmed yet.
        # WARN-only: SKUs get confirmed ad hoc and this firmware may lag behind,
        # so failing here would false-reject a legitimate board.
        if validate_against_spec "$exp_cpu" "$exp_ddr_type" "$exp_ddr_mb" "$exp_emmc_gb" "$exp_wifi"; then
            log "WARN" "MODULE_ID=${module_id} Customer P/N is UNDEFINED (unconfirmed SKU); hardware matches the sheet-defined config"
        else
            log "WARN" "MODULE_ID=${module_id} Customer P/N is UNDEFINED (unconfirmed SKU); hardware does NOT match the sheet-defined config -- check strap/assembly"
        fi
        log "WARN" "If this P/N has since been confirmed, update MODULE_SPEC from the latest sheet 22"
        log "INFO" "Hardware configuration check PASSED (with WARN, unconfirmed MODULE_ID=${module_id})"
        return 0
    fi

    if validate_against_spec "$exp_cpu" "$exp_ddr_type" "$exp_ddr_mb" "$exp_emmc_gb" "$exp_wifi"; then
        log "INFO" "Hardware configuration check PASS"
        return 0
    fi
    log "ERROR" "Hardware configuration check FAIL"
    return 1
}

# Main
test_adc_voltage
rc_voltage=$?

test_core_rev
rc_rev=$?

test_hwcfg
rc_hwcfg=$?

if [ $rc_voltage -eq 0 ] && [ $rc_rev -eq 0 ] && [ $rc_hwcfg -eq 0 ]; then
    log "INFO" "ADC test PASSED"
    exit 0
else
    log "ERROR" "ADC test FAILED (voltage=$rc_voltage core_rev=$rc_rev hwcfg=$rc_hwcfg)"
    exit 1
fi
