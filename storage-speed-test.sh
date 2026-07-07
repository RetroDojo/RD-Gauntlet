#!/system/bin/sh
# storage-speed-test.sh - sequential /sdcard write+read throughput probe.
# Notes:
# - Uses /sdcard only (portable user-writable path, no root).
# - Read speed can be optimistic due to page cache (can't drop caches without root).

COUNT_MB="${1:-100}"
TEST_FILE="${2:-/sdcard/.bench_storage_test}"

case "$COUNT_MB" in
  ''|*[!0-9]*)
    echo '{"status":"error","error":"count_mb_must_be_integer"}'
    exit 1
    ;;
esac

if [ "$COUNT_MB" -le 0 ]; then
  echo '{"status":"error","error":"count_mb_must_be_positive"}'
  exit 1
fi

bytes_total=$((COUNT_MB * 1048576))

calc_mbps() {
  awk -v bytes="$1" -v nanos="$2" 'BEGIN {
    if (nanos <= 0) { print "NA"; exit }
    mbps = (bytes * 1000000000.0 / nanos) / 1048576.0
    printf("%.2f", mbps)
  }'
}

cleanup() {
  rm -f "$TEST_FILE" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

start_ns=$(date +%s%N)
dd if=/dev/zero of="$TEST_FILE" bs=1M count="$COUNT_MB" conv=fsync >/dev/null 2>&1
write_rc=$?
end_ns=$(date +%s%N)
write_ns=$((end_ns - start_ns))

if [ "$write_rc" -ne 0 ]; then
  echo '{"status":"error","error":"write_dd_failed"}'
  exit 2
fi

sync
start_ns=$(date +%s%N)
dd if="$TEST_FILE" of=/dev/null bs=1M >/dev/null 2>&1
read_rc=$?
end_ns=$(date +%s%N)
read_ns=$((end_ns - start_ns))

if [ "$read_rc" -ne 0 ]; then
  echo '{"status":"error","error":"read_dd_failed"}'
  exit 3
fi

write_mbps=$(calc_mbps "$bytes_total" "$write_ns")
read_mbps=$(calc_mbps "$bytes_total" "$read_ns")

echo "{\"status\":\"ok\",\"fileMB\":$COUNT_MB,\"writeMBps\":$write_mbps,\"readMBps\":$read_mbps,\"note\":\"read may be cache-influenced without root cache drop\"}"
