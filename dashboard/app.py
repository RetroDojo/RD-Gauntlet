from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sqlite3
import subprocess
import threading
import time
import webbrowser
from pathlib import Path
from typing import Any

from flask import Flask, abort, jsonify, render_template, request, send_file


DASHBOARD_DIR = Path(__file__).resolve().parent
SUITE_DIR = DASHBOARD_DIR.parent
RESULTS_DIR = SUITE_DIR / "results"
RUNTIME_DIR = DASHBOARD_DIR / "runtime"
LOGS_DIR = DASHBOARD_DIR / "logs"
DB_PATH = DASHBOARD_DIR / "jobs.db"

INVOKE_SCRIPT = SUITE_DIR / "Invoke-BenchmarkSuite.ps1"
COMPARE_DATASET_SCRIPT = SUITE_DIR / "New-ComparisonDataset.ps1"
COMPARE_CHARTS_SCRIPT = SUITE_DIR / "New-ComparisonCharts.ps1"
COMPARE_SCREENSHOTS_SCRIPT = SUITE_DIR / "Compare-Screenshots.py"

app = Flask(__name__, template_folder=str(DASHBOARD_DIR / "templates"))
jobs_lock = threading.Lock()
active_jobs: dict[int, subprocess.Popen[Any]] = {}


def utc_now_iso() -> str:
    return dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def ensure_runtime_dirs() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)


def db_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with db_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL DEFAULT 'suite',
                created_at TEXT NOT NULL,
                device_name TEXT,
                apps_config_path TEXT,
                out_dir TEXT,
                status TEXT NOT NULL,
                pid INTEGER,
                log_path TEXT,
                result_dir TEXT,
                started_at TEXT,
                finished_at TEXT,
                extra_args TEXT
            )
            """
        )


def safe_rel_to_suite(path_text: str) -> Path:
    candidate = Path(path_text)
    if candidate.is_absolute():
        resolved = candidate.resolve()
    else:
        resolved = (SUITE_DIR / candidate).resolve()
    try:
        resolved.relative_to(SUITE_DIR.resolve())
    except Exception:
        abort(400, description="Path must stay under device-bench-suite.")
    return resolved


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def parse_devices() -> list[dict[str, Any]]:
    devices = read_json(SUITE_DIR / "devices.json")
    return devices if isinstance(devices, list) else []


def list_apps_configs() -> list[str]:
    names = sorted([p.name for p in SUITE_DIR.glob("apps*.json") if p.is_file()])
    return names


def list_existing_reports() -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    if not RESULTS_DIR.exists():
        return items
    for report in RESULTS_DIR.rglob("report.md"):
        rel = report.relative_to(SUITE_DIR).as_posix()
        items.append(
            {
                "report_path": rel,
                "run_dir": report.parent.relative_to(SUITE_DIR).as_posix(),
            }
        )
    return sorted(items, key=lambda x: x["run_dir"], reverse=True)


def list_screenshot_candidates(limit: int = 200) -> list[str]:
    if not RESULTS_DIR.exists():
        return []
    files: list[str] = []
    for ext in ("*.png", "*.jpg", "*.jpeg"):
        for p in RESULTS_DIR.rglob(ext):
            files.append(p.relative_to(SUITE_DIR).as_posix())
            if len(files) >= limit:
                return sorted(files)
    return sorted(files)


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    d = dict(row)
    now = dt.datetime.utcnow()
    started_at = d.get("started_at")
    finished_at = d.get("finished_at")
    elapsed_sec = None
    if started_at:
        try:
            start_dt = dt.datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            end_dt = (
                dt.datetime.fromisoformat(finished_at.replace("Z", "+00:00"))
                if finished_at
                else now.replace(tzinfo=dt.timezone.utc)
            )
            elapsed_sec = int((end_dt - start_dt).total_seconds())
        except Exception:
            elapsed_sec = None
    d["elapsed_sec"] = elapsed_sec
    return d


def fetch_job(job_id: int) -> dict[str, Any]:
    with db_conn() as conn:
        row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        if not row:
            abort(404, description="Job not found")
        return row_to_dict(row)


def update_job(job_id: int, **fields: Any) -> None:
    if not fields:
        return
    cols = ", ".join([f"{k} = ?" for k in fields.keys()])
    values = list(fields.values()) + [job_id]
    with db_conn() as conn:
        conn.execute(f"UPDATE jobs SET {cols} WHERE id = ?", values)


def insert_job(
    *,
    kind: str,
    device_name: str | None,
    apps_config_path: str | None,
    out_dir: str | None,
    log_path: str,
    extra_args: dict[str, Any],
) -> int:
    with db_conn() as conn:
        cur = conn.execute(
            """
            INSERT INTO jobs (
                kind, created_at, device_name, apps_config_path, out_dir,
                status, pid, log_path, result_dir, started_at, finished_at, extra_args
            ) VALUES (?, ?, ?, ?, ?, 'queued', NULL, ?, ?, NULL, NULL, ?)
            """,
            (
                kind,
                utc_now_iso(),
                device_name,
                apps_config_path,
                out_dir,
                log_path,
                out_dir,
                json.dumps(extra_args),
            ),
        )
        return int(cur.lastrowid)


def base_suite_command(
    device_name: str,
    apps_config_path: Path,
    out_dir: Path,
    skip_monkey: bool,
    mute_audio: bool,
) -> list[str]:
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(INVOKE_SCRIPT),
        "-DeviceName",
        device_name,
        "-AppsConfig",
        str(apps_config_path),
        "-OutDir",
        str(out_dir),
        "-MuteAudio",
        "1" if mute_audio else "0",
    ]
    if skip_monkey:
        cmd.append("-SkipMonkey")
    return cmd


def make_wrapper_with_device_override(
    *,
    job_id: int,
    device_name: str,
    apps_config_path: Path,
    out_dir: Path,
    skip_monkey: bool,
    mute_audio: bool,
    check_stick_drift: bool,
    sample_haptics: bool,
    apply_device_override: bool,
) -> Path:
    wrapper_path = RUNTIME_DIR / f"run-job-{job_id}.ps1"
    skip_text = "-SkipMonkey" if skip_monkey else ""
    mute_text = "1" if mute_audio else "0"
    if apply_device_override:
        script = f"""$ErrorActionPreference = 'Stop'
$devicesPath = '{str(SUITE_DIR / "devices.json").replace("'", "''")}'
$backup = Get-Content -LiteralPath $devicesPath -Raw
try {{
  $devices = $backup | ConvertFrom-Json
  foreach ($d in $devices) {{
    if ($d.name -eq '{device_name.replace("'", "''")}') {{
      $d.checkStickDrift = ${str(check_stick_drift).lower()}
      $d.sampleHaptics = ${str(sample_haptics).lower()}
    }}
  }}
  [System.IO.File]::WriteAllText($devicesPath, ($devices | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
  & '{str(INVOKE_SCRIPT).replace("'", "''")}' -DeviceName '{device_name.replace("'", "''")}' -AppsConfig '{str(apps_config_path).replace("'", "''")}' -OutDir '{str(out_dir).replace("'", "''")}' -MuteAudio {mute_text} {skip_text}
  exit $LASTEXITCODE
}}
finally {{
  [System.IO.File]::WriteAllText($devicesPath, $backup, [System.Text.UTF8Encoding]::new($false))
}}
"""
    else:
        script = f"""$ErrorActionPreference = 'Stop'
& '{str(INVOKE_SCRIPT).replace("'", "''")}' -DeviceName '{device_name.replace("'", "''")}' -AppsConfig '{str(apps_config_path).replace("'", "''")}' -OutDir '{str(out_dir).replace("'", "''")}' -MuteAudio {mute_text} {skip_text}
exit $LASTEXITCODE
"""
    wrapper_path.write_text(script, encoding="utf-8")
    return wrapper_path


def launch_job_process(job_id: int, command: list[str], cwd: Path, log_path: Path) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = open(log_path, "a", encoding="utf-8", buffering=1)
    log_file.write(f"[{utc_now_iso()}] Launching command:\n{' '.join(command)}\n\n")
    process = subprocess.Popen(
        command,
        cwd=str(cwd),
        stdout=log_file,
        stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP") else 0,
    )
    with jobs_lock:
        active_jobs[job_id] = process
    update_job(job_id, pid=process.pid, status="running", started_at=utc_now_iso())
    return process.pid


def basic_markdown_to_html(text: str) -> str:
    # Basic markdown rendering only; intentionally lightweight/stdlib-only.
    lines = text.splitlines()
    out: list[str] = []
    in_code = False
    in_ul = False

    def inline_format(s: str) -> str:
        s = html.escape(s)
        s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        return s

    for line in lines:
        if line.strip().startswith("```"):
            if in_code:
                out.append("</code></pre>")
            else:
                out.append("<pre><code>")
            in_code = not in_code
            continue
        if in_code:
            out.append(html.escape(line))
            continue
        if line.startswith("- "):
            if not in_ul:
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{inline_format(line[2:])}</li>")
            continue
        if in_ul:
            out.append("</ul>")
            in_ul = False
        if not line.strip():
            out.append("<br>")
            continue
        if line.startswith("### "):
            out.append(f"<h3>{inline_format(line[4:])}</h3>")
        elif line.startswith("## "):
            out.append(f"<h2>{inline_format(line[3:])}</h2>")
        elif line.startswith("# "):
            out.append(f"<h1>{inline_format(line[2:])}</h1>")
        else:
            out.append(f"<p>{inline_format(line)}</p>")
    if in_ul:
        out.append("</ul>")
    if in_code:
        out.append("</code></pre>")
    return "\n".join(out)


def mark_stale_running_jobs() -> None:
    with db_conn() as conn:
        conn.execute(
            """
            UPDATE jobs
            SET status = 'failed', finished_at = ?
            WHERE status IN ('queued', 'running')
            """,
            (utc_now_iso(),),
        )


def poller() -> None:
    while True:
        try:
            with jobs_lock:
                tracked = list(active_jobs.items())
            for job_id, proc in tracked:
                code = proc.poll()
                if code is None:
                    continue
                status = "success" if code == 0 else "failed"
                update_job(job_id, status=status, finished_at=utc_now_iso())
                with jobs_lock:
                    active_jobs.pop(job_id, None)
        except Exception:
            pass
        time.sleep(2)


@app.route("/")
def index() -> str:
    return render_template("index.html")


@app.route("/api/devices")
def api_devices() -> Any:
    return jsonify(parse_devices())


@app.route("/api/apps-configs")
def api_apps_configs() -> Any:
    return jsonify(list_apps_configs())


@app.route("/api/existing-reports")
def api_existing_reports() -> Any:
    return jsonify(list_existing_reports())


@app.route("/api/screenshot-files")
def api_screenshot_files() -> Any:
    return jsonify(list_screenshot_candidates())


@app.route("/api/jobs")
def api_jobs() -> Any:
    with db_conn() as conn:
        rows = conn.execute("SELECT * FROM jobs ORDER BY id DESC").fetchall()
    return jsonify([row_to_dict(r) for r in rows])


@app.route("/api/jobs/<int:job_id>")
def api_job(job_id: int) -> Any:
    return jsonify(fetch_job(job_id))


@app.route("/api/jobs/<int:job_id>/log")
def api_job_log(job_id: int) -> Any:
    lines = max(10, min(1000, int(request.args.get("lines", "200"))))
    job = fetch_job(job_id)
    log_path = Path(job["log_path"]) if job.get("log_path") else None
    if not log_path or not log_path.exists():
        return jsonify({"job_id": job_id, "lines": [], "text": ""})
    content = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    tail = content[-lines:]
    return jsonify({"job_id": job_id, "lines": tail, "text": "\n".join(tail)})


@app.post("/api/run")
def api_run() -> Any:
    payload = request.get_json(force=True)
    device_name = str(payload.get("deviceName", "")).strip()
    apps_config_name = str(payload.get("appsConfig", "")).strip()
    skip_monkey = bool(payload.get("skipMonkey", False))
    mute_audio = bool(payload.get("muteAudio", True))
    capture_storage_speed = bool(payload.get("captureStorageSpeed", False))
    capture_wifi_throughput = bool(payload.get("captureWifiThroughput", False))
    capture_perfetto = bool(payload.get("capturePerfetto", False))
    check_stick_drift = bool(payload.get("checkStickDrift", False))
    sample_haptics = bool(payload.get("sampleHaptics", False))

    if not device_name:
        abort(400, description="deviceName is required")
    if not apps_config_name:
        abort(400, description="appsConfig is required")

    source_apps = safe_rel_to_suite(apps_config_name)
    if not source_apps.exists():
        abort(400, description="Selected apps config does not exist.")
    apps = read_json(source_apps)
    if not isinstance(apps, list):
        abort(400, description="Apps config must be a JSON array.")

    ts = dt.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    out_dir = RESULTS_DIR / f"dashboard-{ts}-{re.sub(r'[^A-Za-z0-9._-]+', '_', device_name)}"
    out_dir.mkdir(parents=True, exist_ok=True)

    log_path = LOGS_DIR / "pending.log"
    extra_args = {
        "skipMonkey": skip_monkey,
        "muteAudio": mute_audio,
        "captureStorageSpeed": capture_storage_speed,
        "captureWifiThroughput": capture_wifi_throughput,
        "capturePerfetto": capture_perfetto,
        "checkStickDrift": check_stick_drift,
        "sampleHaptics": sample_haptics,
        "sourceAppsConfig": source_apps.relative_to(SUITE_DIR).as_posix(),
    }
    job_id = insert_job(
        kind="suite",
        device_name=device_name,
        apps_config_path=source_apps.relative_to(SUITE_DIR).as_posix(),
        out_dir=out_dir.relative_to(SUITE_DIR).as_posix(),
        log_path=str(log_path),
        extra_args=extra_args,
    )

    log_path = LOGS_DIR / f"{job_id}.log"
    update_job(job_id, log_path=str(log_path))

    for app_entry in apps:
        if isinstance(app_entry, dict):
            app_entry["captureStorageSpeed"] = capture_storage_speed
            app_entry["captureWifiThroughput"] = capture_wifi_throughput
            app_entry["capturePerfetto"] = capture_perfetto

    generated_apps = RUNTIME_DIR / f"apps-job-{job_id}.json"
    save_json(generated_apps, apps)

    wrapper = make_wrapper_with_device_override(
        job_id=job_id,
        device_name=device_name,
        apps_config_path=generated_apps,
        out_dir=out_dir,
        skip_monkey=skip_monkey,
        mute_audio=mute_audio,
        check_stick_drift=check_stick_drift,
        sample_haptics=sample_haptics,
        apply_device_override=(check_stick_drift or sample_haptics),
    )
    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(wrapper),
    ]

    launch_job_process(job_id, command, SUITE_DIR, log_path)
    return jsonify({"ok": True, "jobId": job_id})


@app.post("/api/run-comparison")
def api_run_comparison() -> Any:
    log_path = LOGS_DIR / "pending.log"
    job_id = insert_job(
        kind="comparison",
        device_name=None,
        apps_config_path=None,
        out_dir=(RESULTS_DIR / "comparison-charts").relative_to(SUITE_DIR).as_posix(),
        log_path=str(log_path),
        extra_args={"pipeline": ["New-ComparisonDataset.ps1", "New-ComparisonCharts.ps1"]},
    )

    log_path = LOGS_DIR / f"{job_id}.log"
    wrapper = RUNTIME_DIR / f"comparison-job-{job_id}.ps1"
    wrapper.write_text(
        f"""$ErrorActionPreference = 'Stop'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '{str(COMPARE_DATASET_SCRIPT).replace("'", "''")}' -ResultsRoot '{str(RESULTS_DIR).replace("'", "''")}'
if ($LASTEXITCODE -ne 0) {{ exit $LASTEXITCODE }}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '{str(COMPARE_CHARTS_SCRIPT).replace("'", "''")}' -ResultsRoot '{str(RESULTS_DIR).replace("'", "''")}'
exit $LASTEXITCODE
""",
        encoding="utf-8",
    )
    update_job(job_id, log_path=str(log_path))
    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(wrapper),
    ]
    launch_job_process(job_id, command, SUITE_DIR, log_path)
    return jsonify({"ok": True, "jobId": job_id})


@app.post("/api/jobs/<int:job_id>/cancel")
def api_cancel_job(job_id: int) -> Any:
    job = fetch_job(job_id)
    if job["status"] != "running":
        return jsonify({"ok": False, "message": f"Job status is {job['status']}."}), 400

    with jobs_lock:
        proc = active_jobs.get(job_id)
    if not proc:
        return jsonify({"ok": False, "message": "No active process found."}), 404

    subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], check=False, capture_output=True)
    update_job(job_id, status="cancelled", finished_at=utc_now_iso())
    with jobs_lock:
        active_jobs.pop(job_id, None)
    return jsonify({"ok": True, "jobId": job_id})


@app.route("/report")
def report_view() -> Any:
    report_rel = request.args.get("path", "")
    report_path = safe_rel_to_suite(report_rel)
    if report_path.name.lower() != "report.md" or not report_path.exists():
        abort(404)
    text = report_path.read_text(encoding="utf-8", errors="replace")
    rendered = basic_markdown_to_html(text)
    return (
        f"<html><head><meta charset='utf-8'><title>{html.escape(report_rel)}</title>"
        "<style>body{font-family:Segoe UI,Arial,sans-serif;padding:18px;max-width:1100px;margin:auto;}code{background:#f2f2f2;padding:2px 4px;border-radius:4px;}pre{background:#111;color:#eee;padding:10px;overflow:auto;}table{border-collapse:collapse;}td,th{border:1px solid #ddd;padding:4px 8px;}</style>"
        "</head><body>"
        f"<p><a href='/'>Back to dashboard</a></p><h1>{html.escape(report_rel)}</h1>{rendered}</body></html>"
    )


@app.route("/browse")
def browse_result_dir() -> Any:
    rel = request.args.get("path", "results")
    folder = safe_rel_to_suite(rel)
    if not folder.exists() or not folder.is_dir():
        abort(404)
    entries = sorted(folder.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
    rows = []
    if folder != SUITE_DIR:
        parent = folder.parent.relative_to(SUITE_DIR).as_posix()
        rows.append(f"<li><a href='/browse?path={html.escape(parent)}'>.. (parent)</a></li>")
    for e in entries:
        rel_e = e.relative_to(SUITE_DIR).as_posix()
        if e.is_dir():
            rows.append(f"<li>📁 <a href='/browse?path={html.escape(rel_e)}'>{html.escape(e.name)}</a></li>")
        else:
            rows.append(f"<li>📄 <a href='/files?path={html.escape(rel_e)}'>{html.escape(e.name)}</a></li>")
    return (
        "<html><head><meta charset='utf-8'><title>Browse results</title></head>"
        "<body style='font-family:Segoe UI,Arial,sans-serif;padding:18px;'>"
        "<p><a href='/'>Back to dashboard</a></p>"
        f"<h2>{html.escape(folder.relative_to(SUITE_DIR).as_posix())}</h2><ul>{''.join(rows)}</ul></body></html>"
    )


@app.route("/files")
def file_serve() -> Any:
    rel = request.args.get("path", "")
    path = safe_rel_to_suite(rel)
    if not path.exists() or not path.is_file():
        abort(404)
    return send_file(path)


@app.route("/suite-file/<path:filename>")
def suite_file(filename: str) -> Any:
    path = safe_rel_to_suite(filename)
    if not path.exists() or not path.is_file():
        abort(404)
    return send_file(path)


@app.post("/api/tools/compare-screenshots")
def api_compare_screenshots() -> Any:
    payload = request.get_json(force=True)
    img_a = safe_rel_to_suite(str(payload.get("imageA", "")))
    img_b = safe_rel_to_suite(str(payload.get("imageB", "")))
    if not img_a.exists() or not img_b.exists():
        abort(400, description="Both screenshots must exist.")

    cmd = ["python", str(COMPARE_SCREENSHOTS_SCRIPT), str(img_a), str(img_b)]
    proc = subprocess.run(cmd, cwd=str(SUITE_DIR), capture_output=True, text=True)
    return jsonify(
        {
            "exitCode": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "command": " ".join(cmd),
        }
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local dashboard for device bench suite.")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)")
    parser.add_argument("--port", default=8787, type=int, help="Bind port (default: 8787)")
    parser.add_argument("--no-browser", action="store_true", help="Do not auto-open browser.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    ensure_runtime_dirs()
    init_db()
    mark_stale_running_jobs()
    t = threading.Thread(target=poller, daemon=True)
    t.start()
    if not args.no_browser:
        url = f"http://{args.host}:{args.port}/"
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    app.run(host=args.host, port=args.port, debug=False, use_reloader=False)


if __name__ == "__main__":
    main()
