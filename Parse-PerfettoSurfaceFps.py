#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: Parse-PerfettoSurfaceFps.py <trace_path> <package> <out_json>", file=sys.stderr)
        return 1

    trace_path = Path(sys.argv[1])
    package = sys.argv[2]
    out_json = Path(sys.argv[3])

    result = {
        "status": "unsupported",
        "package": package,
        "fpsEstimate": None,
        "frameCount": 0,
        "sourceTable": None,
        "note": "Trace parsed, but no package-matched frame timeline rows were found."
    }

    if not trace_path.exists():
        result["status"] = "error"
        result["note"] = f"Trace file not found: {trace_path}"
        out_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
        return 2

    try:
        from perfetto.trace_processor import TraceProcessor
    except Exception as exc:
        result["status"] = "error"
        result["note"] = f"Missing perfetto Python package: {exc}"
        out_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
        return 3

    try:
        tp = TraceProcessor(file_path=str(trace_path))
        tables = {row.name for row in tp.query("select name from sqlite_master where type='table'")}
        target_table = None
        if "actual_frame_timeline_slice" in tables:
            target_table = "actual_frame_timeline_slice"
        elif "frame_timeline_slice" in tables:
            target_table = "frame_timeline_slice"

        if target_table is None:
            result["status"] = "unsupported"
            result["note"] = "No frame timeline table found in trace."
            out_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
            return 0

        cols = {row.name for row in tp.query(f"PRAGMA table_info({target_table})")}
        predicates = []
        pkg_lit = package.lower().replace("'", "''")
        if "layer_name" in cols:
            predicates.append(f"lower(COALESCE(layer_name, '')) LIKE '%{pkg_lit}%'")
        if "process_name" in cols:
            predicates.append(f"lower(COALESCE(process_name, '')) LIKE '%{pkg_lit}%'")
        if "name" in cols:
            predicates.append(f"lower(COALESCE(name, '')) LIKE '%{pkg_lit}%'")

        if predicates:
            where_clause = " OR ".join(predicates)
        else:
            where_clause = "1=1"

        sql = f"SELECT ts FROM {target_table} WHERE {where_clause} ORDER BY ts"
        rows = list(tp.query(sql))
        result["sourceTable"] = target_table
        result["frameCount"] = len(rows)

        if len(rows) >= 2:
            first_ts = rows[0].ts
            last_ts = rows[-1].ts
            if last_ts > first_ts:
                fps = (len(rows) - 1) / ((last_ts - first_ts) / 1_000_000_000.0)
                result["fpsEstimate"] = round(fps, 2)
                result["status"] = "ok"
                result["note"] = "FPS estimated from package-matched frame timeline rows."
            else:
                result["status"] = "unsupported"
                result["note"] = "Frame timestamps did not advance."
        else:
            result["status"] = "unsupported"
            result["note"] = "Insufficient package-matched frame rows to compute FPS."
    except Exception as exc:
        result["status"] = "error"
        result["note"] = f"Perfetto parse failure: {exc}"

    out_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
