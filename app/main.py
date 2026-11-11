import os
import time

from fastapi import FastAPI
from fastapi.responses import HTMLResponse

START = time.time()


def get_version():
    ver = os.getenv("APP_VERSION")
    if ver and ver != "dev":
        return ver
    try:
        import subprocess

        res = subprocess.run(
            ["git", "rev-parse", "--short=8", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except Exception:
        pass
    return "dev"


VERSION = get_version()

app = FastAPI(title="FastAPI CI/CD on AWS ECS", version=VERSION)


@app.get("/", response_class=HTMLResponse)
def root():
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>FastAPI on AWS ECS Fargate</title>
      <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body class="bg-slate-950 text-slate-100 min-h-screen flex items-center justify-center p-6">
      <div class="max-w-xl w-full bg-slate-900 border border-slate-800 rounded-2xl shadow-2xl p-8 space-y-6">
        <div class="flex items-center justify-between border-b border-slate-800 pb-4">
          <div class="flex items-center space-x-3">
            <span class="inline-flex h-3 w-3 rounded-full bg-emerald-400 animate-ping"></span>
            <span class="text-sm font-semibold text-emerald-400 uppercase tracking-wider">System Live</span>
          </div>
          <span class="text-xs bg-slate-800 text-slate-400 px-3 py-1 rounded-full font-mono">AWS Fargate</span>
        </div>

        <div>
          <h1 class="text-3xl font-extrabold tracking-tight text-white">FastAPI Cloud Microservice</h1>
          <p class="text-slate-400 text-sm mt-1">Automated CI/CD deployment via Jenkins, Docker, ECR & ECS.</p>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="bg-slate-950/60 border border-slate-800/80 p-4 rounded-xl">
            <span class="text-xs text-slate-500 font-medium">Git SHA / Version</span>
            <p class="text-lg font-mono font-bold text-sky-400 mt-1">{VERSION}</p>
          </div>
          <div class="bg-slate-950/60 border border-slate-800/80 p-4 rounded-xl">
            <span class="text-xs text-slate-500 font-medium">AWS Region</span>
            <p class="text-lg font-mono font-bold text-indigo-400 mt-1">ap-south-1</p>
          </div>
        </div>

        <div class="space-y-3 pt-2">
          <a href="/docs" class="block w-full text-center bg-sky-500 hover:bg-sky-400 text-slate-950 font-semibold py-3 rounded-xl transition shadow-lg shadow-sky-500/20">
            Open Interactive Swagger Docs (/docs)
          </a>
          <div class="flex gap-3">
            <a href="/health" class="flex-1 text-center bg-slate-800 hover:bg-slate-700 text-slate-200 text-sm font-medium py-2.5 rounded-xl border border-slate-700/60 transition">
              Health Check (/health)
            </a>
            <a href="/version" class="flex-1 text-center bg-slate-800 hover:bg-slate-700 text-slate-200 text-sm font-medium py-2.5 rounded-xl border border-slate-700/60 transition">
              Version API (/version)
            </a>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": get_version(), "uptime_seconds": round(time.time() - START, 1)}


# Demo live update Wed Nov  4 08:44:27 PM IST 2026

# Manual test update Wed Nov  4 08:53:08 PM IST 2026
# Demo update Thu Nov  5 07:18:42 PM IST 2026

# Live Telemetry Update Thu Nov 12 12:43:35 AM IST 2026 — Release v2.0
