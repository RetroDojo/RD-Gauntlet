#!/system/bin/sh
# perfetto-surfaceview-fps.sh
# Captures a short Perfetto trace with SurfaceFlinger frame + frametimeline
# data sources. Parsing is done host-side.
#
# Usage: sh perfetto-surfaceview-fps.sh <package> [duration_sec] [trace_path]

PKG="$1"
DURATION_SEC="${2:-15}"
TRACE_PATH="${3:-/data/misc/perfetto-traces/surfaceview-fps.perfetto-trace}"
CFG_PATH="/data/local/tmp/perfetto_surfaceview_fps.cfg"

if [ -z "$PKG" ]; then
  echo "status=error"
  echo "error=missing_package"
  exit 1
fi

case "$DURATION_SEC" in
  ''|*[!0-9]*)
    echo "status=error"
    echo "error=duration_must_be_integer"
    exit 1
    ;;
esac

if [ "$DURATION_SEC" -le 0 ]; then
  DURATION_SEC=15
fi

DURATION_MS=$((DURATION_SEC * 1000))

cat > "$CFG_PATH" <<EOF
buffers {
  size_kb: 32768
  fill_policy: RING_BUFFER
}
duration_ms: $DURATION_MS
write_into_file: true
flush_period_ms: 5000
data_sources {
  config {
    name: "android.surfaceflinger.frame"
  }
}
data_sources {
  config {
    name: "android.surfaceflinger.frametimeline"
  }
}
EOF

perfetto -c "$CFG_PATH" --txt -o "$TRACE_PATH" >/dev/null 2>&1
rc=$?
rm -f "$CFG_PATH" >/dev/null 2>&1

if [ "$rc" -ne 0 ]; then
  echo "status=error"
  echo "error=perfetto_capture_failed"
  echo "package=$PKG"
  echo "trace_path=$TRACE_PATH"
  exit 2
fi

if [ ! -f "$TRACE_PATH" ]; then
  echo "status=error"
  echo "error=trace_not_created"
  echo "package=$PKG"
  echo "trace_path=$TRACE_PATH"
  exit 3
fi

echo "status=ok"
echo "package=$PKG"
echo "duration_sec=$DURATION_SEC"
echo "trace_path=$TRACE_PATH"
