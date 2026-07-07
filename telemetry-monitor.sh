#!/system/bin/sh
# telemetry-monitor.sh - portable Android hardware telemetry sampler.
# Auto-discovers CPU/GPU/thermal/fan/battery sysfs nodes at start (works across
# SoC vendors: Qualcomm/Adreno, Mali/Rockchip, Unisoc, MediaTek) so the same
# script runs unmodified on any Android handheld.
#
# Usage: telemetry-monitor.sh <output_csv_path> [interval_seconds]
# Runs until killed (SIGTERM / `pkill -f telemetry-monitor.sh`).

OUT="$1"
INTERVAL="${2:-2}"

if [ -z "$OUT" ]; then
  echo "usage: telemetry-monitor.sh <output_csv> [interval_seconds]" >&2
  exit 1
fi

CPUS=$(ls -d /sys/devices/system/cpu/cpu[0-9]*/cpufreq 2>/dev/null)
CPU_STAT_CORES=$(awk '/^cpu[0-9]+ /{printf "%s ", $1}' /proc/stat 2>/dev/null)

GPU_BUSY=""
GPU_FREQ=""
if [ -f /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage ]; then
  GPU_BUSY=/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage
  GPU_FREQ=/sys/class/kgsl/kgsl-3d0/gpuclk
elif [ -f /sys/class/misc/mali0/device/utilization ]; then
  GPU_BUSY=/sys/class/misc/mali0/device/utilization
  GPU_FREQ=/sys/class/misc/mali0/device/cur_freq
elif [ -f /sys/kernel/gpu/gpu_busy ]; then
  GPU_BUSY=/sys/kernel/gpu/gpu_busy
  GPU_FREQ=/sys/kernel/gpu/gpu_clock
else
  # Generic devfreq fallback (Unisoc/MediaTek/other non-Adreno, non-Mali-legacy
  # SoCs commonly expose GPU clock scaling here; node name varies by SoC, e.g.
  # "23140000.gpu" on Unisoc ums9620, so search by device name suffix rather
  # than hardcoding the address prefix). No generic busy% file is exposed by
  # this framework, only clock - so GPU_BUSY stays empty on this fallback path.
  for d in /sys/class/devfreq/*.gpu /sys/class/devfreq/*gpu*; do
    if [ -f "$d/cur_freq" ]; then
      GPU_FREQ="$d/cur_freq"
      break
    fi
  done
fi

FAN_SPEED=""
FAN_IS_PWM_DUTY=0
for f in /sys/class/gpio5_pwm2/speed /sys/devices/platform/fan/fan_speed; do
  if [ -f "$f" ]; then
    FAN_SPEED="$f"
    break
  fi
done
if [ -z "$FAN_SPEED" ]; then
  # Search all hwmon instances (index varies by device) for either an RPM
  # report (fan1_input) or a PWM duty-cycle value (pwm1 - common on Unisoc
  # "pwm-fan" driver, which does not report RPM, only commanded duty 0-255).
  for h in /sys/class/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    if [ -f "$h/fan1_input" ]; then
      FAN_SPEED="$h/fan1_input"
      break
    elif [ -f "$h/pwm1" ]; then
      FAN_SPEED="$h/pwm1"
      FAN_IS_PWM_DUTY=1
      break
    fi
  done
fi

BATT_TEMP=/sys/class/power_supply/battery/temp
BATT_CURR=/sys/class/power_supply/battery/current_now
BATT_LEVEL=/sys/class/power_supply/battery/capacity
BATT_CHARGE_COUNTER=/sys/class/power_supply/battery/charge_counter
[ -f "$BATT_TEMP" ] || BATT_TEMP=""
[ -f "$BATT_CURR" ] || BATT_CURR=""
[ -f "$BATT_LEVEL" ] || BATT_LEVEL=""
[ -f "$BATT_CHARGE_COUNTER" ] || BATT_CHARGE_COUNTER=""

zone_list=""
for tz in /sys/class/thermal/thermal_zone*; do
  [ -d "$tz" ] || continue
  type=$(cat "$tz/type" 2>/dev/null)
  [ -z "$type" ] && continue
  safe_type=$(echo "$type" | tr -c 'A-Za-z0-9_' '_')
  zone_list="$zone_list $tz|$safe_type"
done

header="timestamp"
for c in $CPUS; do
  n=$(basename "$(dirname "$c")")
  header="$header,${n}_freq_khz"
done
header="$header,cpu_total_util_pct"
for cpu in $CPU_STAT_CORES; do
  header="$header,${cpu}_util_pct"
done
[ -n "$GPU_BUSY" ] && header="$header,gpu_busy_pct"
[ -n "$GPU_FREQ" ] && header="$header,gpu_freq_hz"
if [ -n "$FAN_SPEED" ]; then
  if [ "$FAN_IS_PWM_DUTY" = "1" ]; then
    # PWM duty cycle (commanded fan power level, typically 0-255), not RPM -
    # column name reflects this so reports don't misreport it as a speed unit.
    header="$header,fan_pwm_duty"
  else
    header="$header,fan_speed_rpm"
  fi
fi
[ -n "$BATT_TEMP" ] && header="$header,batt_temp_c"
[ -n "$BATT_CURR" ] && header="$header,batt_current_ua"
[ -n "$BATT_LEVEL" ] && header="$header,batt_level_pct"
# charge_counter is coulomb-counting state (uAh). Delta over time is typically
# more accurate than spot-sampled current_now, which can be noisy/quantized.
header="$header,batt_charge_counter_uah"
for zt in $zone_list; do
  name=$(echo "$zt" | cut -d'|' -f2)
  header="$header,tz_${name}_c"
done

echo "$header" > "$OUT"

PREV_CPU_STAT=/data/local/tmp/telemetry_prev_cpu_stat_$$.txt
CUR_CPU_STAT=/data/local/tmp/telemetry_cur_cpu_stat_$$.txt
awk '/^cpu([0-9]+)? /{print}' /proc/stat 2>/dev/null > "$PREV_CPU_STAT"

cleanup() {
  rm -f "$PREV_CPU_STAT" "$CUR_CPU_STAT" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

while true; do
  awk '/^cpu([0-9]+)? /{print}' /proc/stat 2>/dev/null > "$CUR_CPU_STAT"
  UTIL_LINES=$(awk '
    NR==FNR {
      if ($1 ~ /^cpu([0-9]+)?$/) {
        prev_nf[$1] = NF
        for (i = 2; i <= NF; i++) {
          prev[$1, i] = $i
        }
      }
      next
    }
    $1 ~ /^cpu([0-9]+)?$/ {
      total = 0
      prev_total = 0
      for (i = 2; i <= NF; i++) {
        cur = $i + 0
        total += cur
        pv = prev[$1, i]
        if (pv == "") {
          pv = cur
        }
        prev_total += (pv + 0)
      }

      idle = ($5 + 0)
      iowait = ($6 == "" ? 0 : $6 + 0)
      prev_idle = prev[$1, 5]
      if (prev_idle == "") {
        prev_idle = ($5 + 0)
      }
      prev_iowait = prev[$1, 6]
      if (prev_iowait == "") {
        prev_iowait = ($6 == "" ? 0 : $6 + 0)
      }

      dt = total - prev_total
      di = (idle + iowait) - (prev_idle + prev_iowait)
      if (dt <= 0) {
        util = "NA"
      } else {
        util = sprintf("%.2f", ((dt - di) * 100.0) / dt)
      }
      print $1 "|" util
    }
  ' "$PREV_CPU_STAT" "$CUR_CPU_STAT")

  ts=$(date '+%Y-%m-%d %H:%M:%S')
  row="$ts"
  for c in $CPUS; do
    v=$(cat "$c/scaling_cur_freq" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  done

  v=$(echo "$UTIL_LINES" | grep '^cpu|' | head -n 1 | cut -d'|' -f2)
  [ -z "$v" ] && v="NA"
  row="$row,$v"
  for cpu in $CPU_STAT_CORES; do
    v=$(echo "$UTIL_LINES" | grep "^$cpu|" | head -n 1 | cut -d'|' -f2)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  done

  if [ -n "$GPU_BUSY" ]; then
    v=$(cat "$GPU_BUSY" 2>/dev/null | tr -d ' %')
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  fi
  if [ -n "$GPU_FREQ" ]; then
    v=$(cat "$GPU_FREQ" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  fi
  if [ -n "$FAN_SPEED" ]; then
    v=$(cat "$FAN_SPEED" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  fi
  if [ -n "$BATT_TEMP" ]; then
    v=$(cat "$BATT_TEMP" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  fi
  if [ -n "$BATT_CURR" ]; then
    v=$(cat "$BATT_CURR" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  fi
  if [ -n "$BATT_LEVEL" ]; then
    v=$(cat "$BATT_LEVEL" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  fi
  if [ -n "$BATT_CHARGE_COUNTER" ]; then
    v=$(cat "$BATT_CHARGE_COUNTER" 2>/dev/null)
  else
    v=$(dumpsys battery 2>/dev/null | awk -F': ' '/^[[:space:]]*Charge counter:/ {print $2; exit}')
  fi
  [ -z "$v" ] && v="NA"
  row="$row,$v"
  for zt in $zone_list; do
    tz=$(echo "$zt" | cut -d'|' -f1)
    v=$(cat "$tz/temp" 2>/dev/null)
    [ -z "$v" ] && v="NA"
    row="$row,$v"
  done
  echo "$row" >> "$OUT"
  mv "$CUR_CPU_STAT" "$PREV_CPU_STAT" 2>/dev/null
  sleep "$INTERVAL"
done
