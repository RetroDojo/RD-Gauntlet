#!/system/bin/sh
# wifi-throughput-test.sh - HTTP download throughput probe (internet path).
# Caveat: This measures end-to-end ISP/CDN path, not pure LAN PHY throughput.

URL="$1"
TEST_MB="${2:-25}"

case "$TEST_MB" in
  ''|*[!0-9]*)
    echo '{"status":"error","error":"test_mb_must_be_integer"}'
    exit 1
    ;;
esac

if [ "$TEST_MB" -le 0 ]; then
  echo '{"status":"error","error":"test_mb_must_be_positive"}'
  exit 1
fi

REQUEST_BYTES=$((TEST_MB * 1048576))

if [ -z "$URL" ]; then
  URL="https://speed.cloudflare.com/__down?bytes=$REQUEST_BYTES"
fi

if command -v curl >/dev/null 2>&1; then
  speed_bps=$(curl -L --fail --silent --show-error \
    --connect-timeout 15 --max-time 120 \
    -o /dev/null \
    -w '%{speed_download}' \
    "$URL" 2>/dev/null)
  curl_rc=$?

  if [ "$curl_rc" -eq 0 ] && [ -n "$speed_bps" ]; then
    speed_mbps=$(awk -v bps="$speed_bps" 'BEGIN { printf("%.2f", (bps * 8.0) / 1000000.0) }')
    echo "{\"status\":\"ok\",\"method\":\"curl\",\"url\":\"$URL\",\"bytesRequested\":$REQUEST_BYTES,\"speedBytesPerSec\":$speed_bps,\"speedMbps\":$speed_mbps,\"note\":\"internet-path test; CDN/ISP dependent\"}"
    exit 0
  fi

  echo '{"status":"error","error":"curl_download_failed"}'
  exit 2
fi

if command -v wget >/dev/null 2>&1; then
  echo '{"status":"unsupported","error":"wget_fallback_not_implemented_machine_parsing","note":"curl missing; install curl for numeric throughput output"}'
  exit 3
fi

echo '{"status":"unsupported","error":"no_curl_or_wget"}'
exit 4
