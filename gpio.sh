#!/bin/bash
#
# GPIO Pin Mapping  (base board sheet 13 "GPIO LOOPBACK", core board sheets 7/14/15)
#
# GPIO number = bank * 32 + group * 8 + index   (A=0, B=1, C=2, D=3)
#
# ---- Inverter control outputs -------------------------------------------------
#  ┌────────────────────┬──────────┬──────────┬──────────────────────────────────┐
#  │    网络标号        │  GPIO脚  │ GPIO编号 │ 说明                             │
#  ├────────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ SDMMC0_WPn         │ GPIO0_C3 │ 19       │ U18 inverter input (U18 group)   │
#  ├────────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ LCD_BL_PWM1_CH1_M0 │ GPIO0_B5 │ 13       │ U19 inverter input (U19 group)   │
#  └────────────────────┴──────────┴──────────┴──────────────────────────────────┘
#
# ---- U18 group inputs (12) ---------------------------------------------------
#  ┌─────────────────┬──────────┬──────────┬───────┬───────┐
#  │    网络标号     │  GPIO脚  │ GPIO编号 │  LED  │ 限流  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO5           │ GPIO2_B1 │ 73       │ D30   │ 100R  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO2_C2_d      │ GPIO2_C2 │ 82       │ D28   │ 100R  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO2_C3_d      │ GPIO2_C3 │ 83       │ D29   │ 100R  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ I2C3_SCL_M0     │ GPIO4_B5 │ 141      │ D9    │ 100R  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ I2C3_SDA_M0     │ GPIO4_B4 │ 140      │ D10   │ 100R  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO8           │ GPIO2_B5 │ 77       │ D11   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO9           │ GPIO2_B6 │ 78       │ D12   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO10          │ GPIO2_B7 │ 79       │ D13   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ MUX_SEL_0       │ GPIO2_C1 │ 81       │ D14   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ MUX_SEL_1       │ GPIO2_C6 │ 86       │ D15   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ MUX_SEL_2       │ GPIO2_D1 │ 89       │ D16   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ MUX_SEL_3       │ GPIO2_D4 │ 92       │ D17   │ 1K    │
#  └─────────────────┴──────────┴──────────┴───────┴───────┘
#
# ---- U19 group inputs (10) ---------------------------------------------------
#  ┌─────────────────┬──────────┬──────────┬───────┬───────┐
#  │    网络标号     │  GPIO脚  │ GPIO编号 │  LED  │ 限流  │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDO3_M1    │ GPIO3_C0 │ 112      │ D18   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDO2_M1    │ GPIO3_C1 │ 113      │ D19   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDO1_M1    │ GPIO3_C4 │ 116      │ D20   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDI3_M0    │ GPIO4_B0 │ 136      │ D21   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ AUDIO_CLK_SEL_1 │ GPIO3_A7 │ 103      │ D22   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO3           │ GPIO2_A7 │ 71       │ D23   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ GPIO4           │ GPIO2_B0 │ 72       │ D24   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDI1_M1    │ GPIO3_D4 │ 124      │ D25   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDI2_M1    │ GPIO3_D5 │ 125      │ D26   │ 1K    │
#  ├─────────────────┼──────────┼──────────┼───────┼───────┤
#  │ SAI1_SDI3_M1    │ GPIO3_D6 │ 126      │ D27   │ 1K    │
#  └─────────────────┴──────────┴──────────┴───────┴───────┘
#
# ---- UART loopback pairs (jumper required on the test plate) ------------------
#  ┌─────────────────┬──────────┬──────────┬──────────────────────────────────┐
#  │    网络标号     │  GPIO脚  │ GPIO编号 │ 接口                             │
#  ├─────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ UART3_TX_M0     │ GPIO3_A0 │ 96       │ J10 (UART3)                      │
#  ├─────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ UART3_RX_M0     │ GPIO3_A1 │ 97       │ J10 (UART3)                      │
#  ├─────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ UART3_CTSn_M0   │ GPIO3_A2 │ 98       │ J10 (UART3)                      │
#  ├─────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ UART3_RTSn_M0   │ GPIO3_A3 │ 99       │ J10 (UART3)                      │
#  ├─────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ UART11_TX_M1    │ GPIO2_C4 │ 84       │ J16 (UART11, core board V1.1.0)  │
#  ├─────────────────┼──────────┼──────────┼──────────────────────────────────┤
#  │ UART11_RX_M1    │ GPIO2_C5 │ 85       │ J16 (UART11, core board V1.1.0)  │
#  └─────────────────┴──────────┴──────────┴──────────────────────────────────┘
#

OUTPUT_GPIOS=(13 19)

# U18 group: gated by the U18 inverter, control GPIO 19 (SDMMC0_WPn)
U18_INPUT_GPIOS=(73 82 83 141 140 77 78 79 81 86 89 92)
# U19 group: gated by the U19 inverter, control GPIO 13 (LCD_BL_PWM1_CH1_M0)
U19_INPUT_GPIOS=(112 113 116 136 103 71 72 124 125 126)

INPUT_GPIOS=("${U18_INPUT_GPIOS[@]}" "${U19_INPUT_GPIOS[@]}")
UART_GPIOS=(96 97 98 99 84 85)

declare -A GPIO_NAME=(
    [13]="LCD_BL_PWM1_CH1_M0"
    [19]="SDMMC0_WPn"
    [71]="GPIO3"
    [72]="GPIO4"
    [73]="GPIO5"
    [77]="GPIO8"
    [78]="GPIO9"
    [79]="GPIO10"
    [81]="MUX_SEL_0"
    [82]="GPIO2_C2_d"
    [83]="GPIO2_C3_d"
    [84]="UART11_TX_M1"
    [85]="UART11_RX_M1"
    [86]="MUX_SEL_1"
    [89]="MUX_SEL_2"
    [92]="MUX_SEL_3"
    [96]="UART3_TX_M0"
    [97]="UART3_RX_M0"
    [98]="UART3_CTSn_M0"
    [99]="UART3_RTSn_M0"
    [103]="AUDIO_CLK_SEL_1"
    [112]="SAI1_SDO3_M1"
    [113]="SAI1_SDO2_M1"
    [116]="SAI1_SDO1_M1"
    [124]="SAI1_SDI1_M1"
    [125]="SAI1_SDI2_M1"
    [126]="SAI1_SDI3_M1"
    [136]="SAI1_SDI3_M0"
    [140]="I2C3_SDA_M0"
    [141]="I2C3_SCL_M0"
)

gpio_label() {
    local gpio="$1"
    local name="${GPIO_NAME[$gpio]}"
    if [ -n "$name" ]; then
        echo "GPIO${gpio} (${name})"
    else
        echo "GPIO${gpio}"
    fi
}

SYSFS_GPIO="/sys/class/gpio"
EXPORT_PATH="${SYSFS_GPIO}/export"
UNEXPORT_PATH="${SYSFS_GPIO}/unexport"

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg"
}

export_gpio() {
    local gpio="$1"
    if [ ! -d "${SYSFS_GPIO}/gpio${gpio}" ]; then
        echo "${gpio}" > "${EXPORT_PATH}" 2>/dev/null
        sleep 0.05
        log "INFO" "Exported $(gpio_label ${gpio})"
    fi
}

unexport_gpio() {
    local gpio="$1"
    if [ -d "${SYSFS_GPIO}/gpio${gpio}" ]; then
        echo "${gpio}" > "${UNEXPORT_PATH}" 2>/dev/null
        log "INFO" "Unexported $(gpio_label ${gpio})"
    fi
}

set_gpio_direction() {
    local gpio="$1"
    local dir="$2"
    echo "${dir}" > "${SYSFS_GPIO}/gpio${gpio}/direction" 2>/dev/null
    log "INFO" "Set $(gpio_label ${gpio}) direction to ${dir}"
}

cleanup_all() {
    for gpio in "${OUTPUT_GPIOS[@]}" "${INPUT_GPIOS[@]}" "${UART_GPIOS[@]}"; do
        unexport_gpio "${gpio}"
    done
}

trap cleanup_all EXIT

setup_gpio() {
    for gpio in "${OUTPUT_GPIOS[@]}" "${INPUT_GPIOS[@]}"; do
        export_gpio "${gpio}"
    done
    for gpio in "${OUTPUT_GPIOS[@]}"; do
        set_gpio_direction "${gpio}" out
    done
    for gpio in "${INPUT_GPIOS[@]}"; do
        set_gpio_direction "${gpio}" in
    done
}

gpio_test_cycle() {
    local state="$1"

    if [[ "$state" != "0" && "$state" != "1" ]]; then
        log "ERROR" "gpio_test_cycle: invalid state '${state}', must be 0 or 1"
        return 1
    fi

    local fail_gpios=()
    for gpio in "${OUTPUT_GPIOS[@]}"; do
        echo "${state}" > "${SYSFS_GPIO}/gpio${gpio}/value" 2>/dev/null
        log "INFO" "Set $(gpio_label ${gpio}) output value to ${state}"
    done
    sleep 0.5

    # 由于有反相器，输入GPIO的电平应为输出的反相
    local expected_input
    if [ "$state" = "1" ]; then
        expected_input="0"
    else
        expected_input="1"
    fi

    for gpio in "${INPUT_GPIOS[@]}"; do
        if [ ! -e "${SYSFS_GPIO}/gpio${gpio}/value" ]; then
            log "WARN" "$(gpio_label ${gpio}): not exported or unavailable"
            fail_gpios+=("${gpio}")
            continue
        fi
        local val
        val=$(cat "${SYSFS_GPIO}/gpio${gpio}/value" 2>/dev/null)
        if [ "$val" != "$expected_input" ]; then
            log "ERROR" "$(gpio_label ${gpio}): expected ${expected_input} (inverter), actual ${val}"
            fail_gpios+=("${gpio}")
        else
            log "INFO" "$(gpio_label ${gpio}): expected ${expected_input} (inverter), actual ${val}"
        fi
    done

    if [ ${#fail_gpios[@]} -ne 0 ]; then
        local fail_labels=()
        for g in "${fail_gpios[@]}"; do
            fail_labels+=("$(gpio_label $g)")
        done
        log "ERROR" "Failed GPIOs: ${fail_labels[*]}"
        return 1
    fi
    return 0
}

test_uart_gpio_connectivity() {
    local pairs=(
        "96 97"
        "98 99"
        "84 85"
    )
    local has_failure=0
    local fail_gpios=()

    log "INFO" "==> UART GPIO connectivity test..."

    for pair in "${pairs[@]}"; do
        set -- $pair
        export_gpio "$1"
        export_gpio "$2"
        set_gpio_direction "$1" out
        set_gpio_direction "$2" in
        log "INFO" "Configured $(gpio_label $1) (out) -> $(gpio_label $2) (in)"
    done

    for pair in "${pairs[@]}"; do
        set -- $pair
        local out_gpio="$1"
        local in_gpio="$2"
        local val

        log "INFO" "Testing $(gpio_label ${out_gpio}) -> $(gpio_label ${in_gpio})"

        echo 1 > "${SYSFS_GPIO}/gpio${out_gpio}/value" 2>/dev/null
        sleep 0.1
        val=$(cat "${SYSFS_GPIO}/gpio${in_gpio}/value" 2>/dev/null)
        if [ "$val" = "1" ]; then
            log "INFO" "$(gpio_label ${in_gpio}) read value (should be 1): ${val}"
        else
            log "ERROR" "$(gpio_label ${in_gpio}) read value (should be 1): ${val}"
            has_failure=1
            fail_gpios+=("${in_gpio}")
        fi

        echo 0 > "${SYSFS_GPIO}/gpio${out_gpio}/value" 2>/dev/null
        sleep 0.1
        val=$(cat "${SYSFS_GPIO}/gpio${in_gpio}/value" 2>/dev/null)
        if [ "$val" = "0" ]; then
            log "INFO" "$(gpio_label ${in_gpio}) read value (should be 0): ${val}"
        else
            log "ERROR" "$(gpio_label ${in_gpio}) read value (should be 0): ${val}"
            has_failure=1
            fail_gpios+=("${in_gpio}")
        fi
    done

    for pair in "${pairs[@]}"; do
        set -- $pair
        unexport_gpio "$1"
        unexport_gpio "$2"
    done

    if [ ${#fail_gpios[@]} -ne 0 ]; then
        local fail_labels=()
        local seen=""
        for g in "${fail_gpios[@]}"; do
            if [[ "$seen" != *"|${g}|"* ]]; then
                fail_labels+=("$(gpio_label $g)")
                seen+="|${g}|"
            fi
        done
        log "ERROR" "Failed GPIOs: ${fail_labels[*]}"
    fi

    if [ $has_failure -eq 0 ]; then
        log "INFO" "UART GPIO connectivity test PASSED"
    else
        log "ERROR" "UART GPIO connectivity test FAILED"
    fi
    return $has_failure
}

test_gpio() {
    log "INFO" "==> GPIO signal test..."
    log "INFO" "U18 group (ctrl GPIO 19): ${#U18_INPUT_GPIOS[@]} inputs; U19 group (ctrl GPIO 13): ${#U19_INPUT_GPIOS[@]} inputs"
    setup_gpio
    local has_failure=0

    for i in $(seq 1 3); do
        log "INFO" "Cycle ${i}/3: set output HIGH"
        gpio_test_cycle 1 || has_failure=1
        log "INFO" "Cycle ${i}/3: set output LOW"
        gpio_test_cycle 0 || has_failure=1
        log "INFO" ""
    done

    for gpio in "${OUTPUT_GPIOS[@]}" "${INPUT_GPIOS[@]}"; do
        unexport_gpio "${gpio}"
    done

    if [ $has_failure -eq 0 ]; then
        log "INFO" "GPIO test PASSED"
    else
        log "ERROR" "GPIO test FAILED"
    fi
    return $has_failure
}

main() {
    local final_ret=0

    test_gpio || final_ret=1
    test_uart_gpio_connectivity || final_ret=1

    if [ $final_ret -eq 0 ]; then
        log "INFO" "All tests PASSED"
    else
        log "ERROR" "Some tests FAILED"
    fi
    exit $final_ret
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
