#!/system/bin/sh
# haptic-intensity-check.sh
# Best-effort pure-ADB probe for rumble strength feasibility.
# On many Android builds, shell UID cannot trigger vibrator service directly and
# cannot stream accelerometer samples. In that case this script reports
# "unsupported" honestly instead of fabricating a metric.

accel_present="false"
if dumpsys sensorservice 2>/dev/null | grep -qi 'Accelerometer'; then
  accel_present="true"
fi

vibrator_service=""
if cmd -l 2>/dev/null | grep -q '^vibrator$'; then
  vibrator_service="vibrator"
elif cmd -l 2>/dev/null | grep -q '^vibrator_manager$'; then
  vibrator_service="vibrator_manager"
fi

if [ -z "$vibrator_service" ]; then
  echo "{\"status\":\"unsupported\",\"accelerometerListed\":$accel_present,\"reason\":\"cmd vibrator service unavailable to shell uid on this build\"}"
  exit 0
fi

if [ "$vibrator_service" = "vibrator" ]; then
  cmd vibrator vibrate 250 >/dev/null 2>&1
  vib_rc=$?
else
  cmd vibrator_manager vibrate 250 >/dev/null 2>&1
  vib_rc=$?
fi

if [ "$vib_rc" -ne 0 ]; then
  echo "{\"status\":\"unsupported\",\"accelerometerListed\":$accel_present,\"vibratorService\":\"$vibrator_service\",\"reason\":\"vibrator command exists but shell trigger failed\"}"
  exit 0
fi

if dumpsys sensorservice 2>/dev/null | grep -q '^[[:space:]]*[xyz]=\|accel='; then
  echo "{\"status\":\"partial\",\"accelerometerListed\":$accel_present,\"vibratorService\":\"$vibrator_service\",\"note\":\"vibrator trigger succeeded but robust live accelerometer stream parser is not implemented in pure ADB\"}"
  exit 0
fi

echo "{\"status\":\"unsupported\",\"accelerometerListed\":$accel_present,\"vibratorService\":\"$vibrator_service\",\"reason\":\"no reliable live accelerometer samples via dumpsys sensorservice; companion APK required\"}"
