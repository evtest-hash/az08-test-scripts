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

test_hwcfg() {
    log "INFO" "==> Hardware configuration check (channel 6, 7)"

    local samples="${1:-${SAMPLES:-3}}"
    if ! echo "$samples" | grep -qE '^[0-9]+$'; then
        log "ERROR" "SAMPLES must be integer"
        return 1
    fi
    if [ "$samples" -le 0 ]; then
        log "ERROR" "SAMPLES must be > 0"
        return 1
    fi

    local conf_table
    conf_table=$(
    cat <<'EOF'
CONF_ID1|0|0|RK3576S|LPDDR4X|2048|8|WITH|RK3576S LPDDR4X 2+8GB WITH WIFI+BT
CONF_ID2|0|416|RK3576S|LPDDR4X|2048|8|WITHOUT|RK3576S LPDDR4X 2+8GB WITHOUT WIFI+BT
CONF_ID3|0|816|RK3576|LPDDR4X|2048|8|WITH|RK3576 LPDDR4X 2+8GB WITH WIFI+BT
CONF_ID4|0|1231|RK3576|LPDDR4X|2048|8|WITHOUT|RK3576 LPDDR4X 2+8GB WITHOUT WIFI+BT
CONF_ID5|0|1658|RK3576S|LPDDR4|2048|8|WITH|RK3576S LPDDR4 2+8GB WITH WIFI+BT
CONF_ID6|0|2048|RK3576S|LPDDR4|2048|8|WITHOUT|RK3576S LPDDR4 2+8GB WITHOUT WIFI+BT
CONF_ID7|0|2437|RK3576|LPDDR4|2048|8|WITH|RK3576 LPDDR4 2+8GB WITH WIFI+BT
CONF_ID8|0|2862|RK3576|LPDDR4|2048|8|WITHOUT|RK3576 LPDDR4 2+8GB WITHOUT WIFI+BT
CONF_ID9|0|3279|RK3576S|LPDDR5|2048|8|WITH|RK3576S LPDDR5 2+8GB WITH WIFI+BT
CONF_ID10|0|3680|RK3576S|LPDDR5|2048|8|WITHOUT|RK3576S LPDDR5 2+8GB WITHOUT WIFI+BT
CONF_ID11|0|4095|RK3576|LPDDR5|2048|8|WITH|RK3576 LPDDR5 2+8GB WITH WIFI+BT
CONF_ID12|416|0|RK3576|LPDDR5|2048|8|WITHOUT|RK3576 LPDDR5 2+8GB WITHOUT WIFI+BT
EOF
    )

    # Find ADC device with channel 6, 7
    local adc_dev
    adc_dev="$(find_adc_dev 6 7 || true)"
    if [ -z "$adc_dev" ]; then
        log "ERROR" "No IIO ADC node with voltage6~7 found"
        return 1
    fi

    # Sample ADC channels 6 and 7
    local n adc6_avg adc7_avg adc6_min adc6_max adc7_min adc7_max
    read -r n adc6_avg adc7_avg adc6_min adc6_max adc7_min adc7_max <<<"$(
      i=0
      while [ "$i" -lt "$samples" ]; do
        v6="$(cat "$adc_dev/in_voltage6_raw" 2>/dev/null || echo "")"
        v7="$(cat "$adc_dev/in_voltage7_raw" 2>/dev/null || echo "")"
        echo "$v6" | grep -qE '^[0-9]+$' && echo "$v7" | grep -qE '^[0-9]+$' && echo "$v6 $v7"
        i=$((i + 1))
        usleep 50000 2>/dev/null || sleep 0.05
      done | awk '
        BEGIN { min6=1e9; min7=1e9; max6=-1; max7=-1; }
        NF>=2 {
          v6=$1+0; v7=$2+0; n++; sum6+=v6; sum7+=v7;
          if (v6<min6) min6=v6; if (v6>max6) max6=v6;
          if (v7<min7) min7=v7; if (v7>max7) max7=v7;
        }
        END {
          if (n==0) { print 0,0,0,0,0,0,0; exit }
          printf "%d %.2f %.2f %d %d %d %d\n", n, sum6/n, sum7/n, min6, max6, min7, max7;
        }'
    )"
    if [ -z "$n" ] || ! echo "$n" | grep -qE '^[0-9]+$' || [ "$n" -eq 0 ]; then
        log "ERROR" "No valid channel 6, 7 sample"
        return 1
    fi
    log "INFO" "Channel 6/7 samples: n=$n avg=($adc6_avg, $adc7_avg) range6=[$adc6_min..$adc6_max] range7=[$adc7_min..$adc7_max]"

    # Match ADC values to config table
    local best_raw best_id best_a6 best_a7 best_cpu best_ddr_type best_ddr_mb best_emmc_gb best_wifi best_text best_score second_score
    best_raw="$(
      awk -F'|' -v v6="${adc6_avg}" -v v7="${adc7_avg}" '
        BEGIN { best=999999999999; second=999999999999; best_line="" }
        {
          d6=v6-$2; d7=v7-$3; score=d6*d6+d7*d7
          if (score < best) { second=best; best=score; best_line=$0 }
          else if (score < second) { second=score }
        }
        END { printf "%s|%.4f|%.4f\n", best_line, best, second }' <<<"${conf_table}"
    )"
    IFS='|' read -r best_id best_a6 best_a7 best_cpu best_ddr_type best_ddr_mb best_emmc_gb best_wifi best_text best_score second_score <<<"${best_raw}"

    log "INFO" "Config match: $best_id target=($best_a6, $best_a7) score=$best_score second=$second_score"
    log "INFO" "Hardware configuration: $best_text"

    # Read OTP byte 8 for CPU identification
    local otp_hex=""
    if [ -r /sys/bus/nvmem/devices/rockchip-otp0/nvmem ]; then
        if command -v hexdump >/dev/null 2>&1; then
            otp_hex="$(hexdump -s 8 -n 1 -e '1/1 "0x%02x"' /sys/bus/nvmem/devices/rockchip-otp0/nvmem 2>/dev/null || true)"
        fi
        if [ -z "$otp_hex" ]; then
            otp_hex="$(dd if=/sys/bus/nvmem/devices/rockchip-otp0/nvmem bs=1 skip=8 count=1 2>/dev/null | od -An -tx1 | awk 'NR==1{print "0x"$1}' || true)"
        fi
    fi
    otp_hex="$(echo "${otp_hex}" | tr 'A-Z' 'a-z' | awk 'NR==1{print $1}')"

    local cpu_otp="UNKNOWN" cpu_bin="N/A"
    case "${otp_hex}" in
        0x01) cpu_otp="RK3576";  cpu_bin="0" ;;
        0x13) cpu_otp="RK3576S"; cpu_bin="3" ;;
        0x0a) cpu_otp="RK3576J"; cpu_bin="2" ;;
        0x0d) cpu_otp="RK3576M"; cpu_bin="1" ;;
    esac
    log "INFO" "CPU OTP: byte8=${otp_hex:-N/A} bin=$cpu_bin => $cpu_otp"

    # Read DDR info
    local dmcinfo ddr_type ddr_mb_total
    dmcinfo="$(cat /proc/dmcdbg/dmcinfo 2>/dev/null || true)"
    ddr_type="$(awk -F': *' '/^DramType:/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit}' <<<"${dmcinfo}")"
    ddr_mb_total="$(awk -F': *' '/^TotalSize:/ {sum += ($2+0)} END {print sum+0}' <<<"${dmcinfo}")"
    log "INFO" "DDR: type=${ddr_type:-N/A} capacity=${ddr_mb_total:-0}MB"

    # Read eMMC info
    local emmc_sectors emmc_lba emmc_gib emmc_name
    emmc_sectors="$(awk 'NR==1{print $1+0}' /sys/block/mmcblk0/size 2>/dev/null || echo 0)"
    emmc_lba="$(awk 'NR==1{print $1+0}' /sys/block/mmcblk0/queue/logical_block_size 2>/dev/null || echo 512)"
    [ "$emmc_lba" -gt 0 ] 2>/dev/null || emmc_lba=512
    emmc_gib="$(awk -v s="${emmc_sectors}" -v b="${emmc_lba}" 'BEGIN{printf "%.2f", (s*b)/(1024*1024*1024)}')"
    emmc_name="$(cat /sys/bus/mmc/devices/mmc0:0001/name 2>/dev/null | awk 'NR==1{print $0}')"
    log "INFO" "eMMC: ${emmc_gib}GiB name=${emmc_name:-N/A}"

    # Detect WiFi/BT
    local sdio_count wlan_count bcmdhd_count wifibt_info wifi_present
    sdio_count="$(find /sys/bus/sdio/devices -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | awk '{print $1+0}')"
    if [ -x /usr/bin/wifibt-util.sh ]; then
        wifibt_info="$(/usr/bin/wifibt-util.sh info 2>/dev/null || true)"
    else
        wifibt_info=""
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
    wifi_present=0
    if [ "$sdio_count" -gt 0 ] || [ -n "$wifibt_info" ] || [ "$wlan_count" -gt 0 ] || [ "$bcmdhd_count" -gt 0 ]; then
        wifi_present=1
    fi
    log "INFO" "WiFi: sdio=$sdio_count wlan=$wlan_count bcmdhd=$bcmdhd_count info='$wifibt_info'"

    # Validate CPU
    local pass_cpu="FAIL"
    if [ "$cpu_otp" = "$best_cpu" ]; then
        pass_cpu="PASS"
    fi
    log "INFO" "[CPU]   expect=$best_cpu actual=$cpu_otp => $pass_cpu"

    # Validate DDR type
    local pass_ddr_type="FAIL"
    local ddr_type_upper best_ddr_type_upper
    ddr_type_upper="$(echo "${ddr_type}" | tr '[:lower:]' '[:upper:]')"
    best_ddr_type_upper="$(echo "${best_ddr_type}" | tr '[:lower:]' '[:upper:]')"
    if [ -n "${ddr_type}" ] && [ "${ddr_type_upper}" = "${best_ddr_type_upper}" ]; then
        pass_ddr_type="PASS"
    fi

    # Validate DDR capacity
    local pass_ddr_mb="FAIL"
    if [ -n "${ddr_mb_total}" ] && [ "${ddr_mb_total}" -gt 0 ] 2>/dev/null; then
        local low_mb=$((best_ddr_mb - 128))
        local high_mb=$((best_ddr_mb + 128))
        if [ "${ddr_mb_total}" -ge "$low_mb" ] && [ "${ddr_mb_total}" -le "$high_mb" ]; then
            pass_ddr_mb="PASS"
        fi
    fi
    log "INFO" "[DDR]   expect=$best_ddr_type/${best_ddr_mb}MB actual=${ddr_type:-N/A}/${ddr_mb_total:-0}MB => type:$pass_ddr_type cap:$pass_ddr_mb"

    # Validate eMMC capacity
    local pass_emmc="FAIL"
    local emmc_exp_gib
    emmc_exp_gib="$(awk -v g="${best_emmc_gb}" 'BEGIN{printf "%.2f", (g*1000*1000*1000)/(1024*1024*1024)}')"
    if awk -v real="${emmc_gib}" -v tgt="${emmc_exp_gib}" 'BEGIN{d=real-tgt; if(d<0)d=-d; exit !(d <= 1.20)}'; then
        pass_emmc="PASS"
    fi
    log "INFO" "[eMMC]  expect=${best_emmc_gb}GB(~${emmc_exp_gib}GiB) actual=${emmc_gib}GiB name=${emmc_name:-N/A} => $pass_emmc"

    # Validate WiFi presence
    local pass_wifi="FAIL"
    if [ "${best_wifi}" = "WITHOUT" ]; then
        if [ "$sdio_count" -eq 0 ] && [ -z "$wifibt_info" ] && [ "$wlan_count" -eq 0 ] && [ "$bcmdhd_count" -eq 0 ]; then
            pass_wifi="PASS"
        fi
    else
        if [ "$wifi_present" -eq 1 ]; then
            pass_wifi="PASS"
        fi
    fi
    log "INFO" "[WiFi]  expect=$best_wifi => $pass_wifi"

    # Overall result
    local total_pass="FAIL"
    if [ "$pass_cpu" = "PASS" ] && [ "$pass_ddr_type" = "PASS" ] && [ "$pass_ddr_mb" = "PASS" ] && [ "$pass_emmc" = "PASS" ] && [ "$pass_wifi" = "PASS" ]; then
        total_pass="PASS"
    fi
    log "INFO" "Hardware configuration check $total_pass"

    if [ "$total_pass" = "PASS" ]; then
        return 0
    fi
    return 1
}

# Main
test_adc_voltage
rc_voltage=$?

test_hwcfg
rc_hwcfg=$?

if [ $rc_voltage -eq 0 ] && [ $rc_hwcfg -eq 0 ]; then
    log "INFO" "ADC test PASSED"
    exit 0
else
    log "ERROR" "ADC test FAILED (voltage=$rc_voltage hwcfg=$rc_hwcfg)"
    exit 1
fi
