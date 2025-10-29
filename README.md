# Measure-Requests

PowerShell tooling to:

* Optionally recycle a DNN/IIS site (touch `web.config`) and warm it up.
* Optionally stop the IIS App Pool to unlock files, clean a target folder with retry, then start the pool again.
* Execute a list of URLs in sequence, measuring each request and total run time.
* Optionally repeat the entire set multiple times and compute per-URL statistics.
* Save raw measurements to CSV for later analysis.
* Rebuild HTML summary tables from CSVs (outside this script).

Works on Windows with PowerShell 5.1 or newer (PowerShell 7 supported).

---

## Files

* `Measure-Requests.ps1` – the main script.
* `01-Clean-And-Run-Once.ps1` – single run after recycle/keepalive and a clean.
* `02-Repeat5-TouchAndClean-EachRun.ps1` – five runs; recycle + keepalive + clean before each run.
* `03-Warm-Cache-Run.ps1` – three runs without cleaning or recycle (warm cache).
* `04-Cold-vs-Warm-Comparison.ps1` – 9 cold runs (recycle + clean) then 9 disk runs (recycle) and finish 9 warm in-memory runs.
* Optional `.cmd` launchers that invoke the runners from Windows Explorer as Admin to have permmision for iis apppool recycle.

> The runner scripts assume your DNN site and paths as used below. Adjust URLs and paths as needed.

---

## Prerequisites

* Windows with PowerShell 5.1+ (or PowerShell 7).
* If you want to stop/start an IIS App Pool, run PowerShell as Administrator.
* For HTTPS requests, TLS 1.2+ should be available (the script enables it).

---

## Parameters (Measure-Requests.ps1)

### Core

* `-Urls <string[]>`
  Required list of URLs to measure.

* `-Repeat <int>`
  Number of times to repeat the full set of URLs. Default: `1`.

* `-TimeoutSec <int>`
  HTTP timeout per request. Default: `60`.

* `-DelayMsBetweenRequests <int>`
  Milliseconds to wait between requests within a run. Default: `0`.

* `-DelayMsBetweenRuns <int>`
  Milliseconds to wait between runs. Default: `0`.

### Cleaning & Paths

* `-CleanPath <string>`
  Target folder to delete contents from. Default:
  `C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml`

* `-CleanFirst`
  Clean once before the first run (after recycle/keepalive and before warmup).

* `-CleanEachRun`
  Clean before every run (after recycle/keepalive and before warmup).

* `-DeleteMaxRetries <int>` / `-DeleteRetryDelayMs <int>`
  Robust deletion retries and delay (to handle locked files). Defaults: `10`, `300`.

### Recycle & KeepAlive

* `-WebConfigPath <string>`
  Path to `web.config` to touch. Default:
  `C:\Projects\2sxc\2sxc-dnn\Website\web.config`

* `-TouchWebConfigFirst` / `-TouchWebConfigEachRun`
  Touch `web.config` before the first run and/or before each run.

* `-RecycleWaitSec <int>`
  Seconds to wait immediately after touching `web.config`. Default: `5`.

* `-CallKeepAlive`
  Call a keepalive endpoint after touching `web.config`.

* `-KeepAliveUrl <string>`
  Keepalive endpoint. Default: `https://2sxc-dnn.dnndev.me/keepalive.aspx`

* `-KeepAliveTimeoutSec <int>` / `-KeepAliveRetries <int>` / `-KeepAliveDelayMs <int>`
  Keepalive request control. Defaults: `30`, `3`, `500`.

* `-PostKeepAliveWaitSec <int>`
  Extra wait after a successful keepalive, before cleaning. Default: `5`.

### Optional Warm-Up (non-measured)

* `-CallWarmUp`
  Perform a warm-up request that is not included in measurements.

* `-WarmUpUrl <string>`
  Warm-up URL (for example, a homepage).

* `-WarmUpTimeoutSec <int>` / `-WarmUpRetries <int>` / `-WarmUpDelayMs <int>`
  Warm-up controls. Defaults: `30`, `3`, `500`.

* `-PostWarmUpWaitMs <int>`
  Milliseconds to wait after warm-up completes. Default: `0`.

### IIS App Pool Control (optional)

* `-AppPoolName <string>`
  IIS Application Pool name. When provided with the following switches, the script will stop the pool before deleting and start it again afterward to avoid file locks.

* `-StopAppPoolForCleanFirst` / `-StopAppPoolForCleanEachRun`
  Stop the app pool before the clean, start it again after.

* `-AppPoolWaitStopSec <int>` / `-AppPoolWaitStartSec <int>`
  Waits for pool to reach the desired state. Defaults: `15`, `10`.

> When using app pool stop/start, keepalive will be called only after the pool is started.

### CSV output

* `-SaveCsv`
  Save all raw results to CSV.

* `-CsvPath <string>`
  Path to the CSV file. When not provided, a timestamped CSV is created in the current folder.

---

## Output

Console:

* Per-request lines: URL, status, duration (ms).
* Per-run totals.
* Tables:

  * “All request results” (Run, Url, Ok, Status, DurationMs, ContentLength).
  * “Summary by URL” (Count, AvgMs, MinMs, MaxMs, SuccessPct).
  * “Summary by run” (TotalMs, Success, Count).

CSV (if `-SaveCsv`):

* One row per request with: `Timestamp, Run, Url, Ok, Status, DurationMs, ContentLength, Error`.

---

## Typical Flows

### 1) Single cold run: recycle + keepalive + clean, then measure

```powershell
.\Measure-Requests.ps1 `
  -Urls @(
    "https://2sxc-dnn.dnndev.me/en-us/",
    "https://2sxc-dnn.dnndev.me/en-us/p1",
    "https://2sxc-dnn.dnndev.me/en-us/p2",
    "https://2sxc-dnn.dnndev.me/en-us/p3",
    "https://2sxc-dnn.dnndev.me/en-us/p4",
    "https://2sxc-dnn.dnndev.me/en-us/p5",
    "https://2sxc-dnn.dnndev.me/en-us/p6"
  ) `
  -TouchWebConfigFirst -RecycleWaitSec 5 `
  -CallKeepAlive -PostKeepAliveWaitSec 5 `
  -CleanFirst `
  -SaveCsv -CsvPath .\results\run-once.csv
```

### 2) Five runs, recycle and clean before each run

```powershell
.\Measure-Requests.ps1 `
  -Urls @(
    "https://2sxc-dnn.dnndev.me/en-us/",
    "https://2sxc-dnn.dnndev.me/en-us/p1",
    "https://2sxc-dnn.dnndev.me/en-us/p2",
    "https://2sxc-dnn.dnndev.me/en-us/p3",
    "https://2sxc-dnn.dnndev.me/en-us/p4",
    "https://2sxc-dnn.dnndev.me/en-us/p5",
    "https://2sxc-dnn.dnndev.me/en-us/p6"
  ) `
  -TouchWebConfigEachRun -RecycleWaitSec 5 `
  -CallKeepAlive -PostKeepAliveWaitSec 5 `
  -CleanEachRun `
  -Repeat 5 `
  -DelayMsBetweenRequests 250 -DelayMsBetweenRuns 1000 `
  -SaveCsv -CsvPath .\results\repeat5-touch-clean-each.csv
```

### 3) Warm cache tests (no recycle, no clean)

```powershell
.\Measure-Requests.ps1 `
  -Urls @(
    "https://2sxc-dnn.dnndev.me/en-us/",
    "https://2sxc-dnn.dnndev.me/en-us/p1",
    "https://2sxc-dnn.dnndev.me/en-us/p2",
    "https://2sxc-dnn.dnndev.me/en-us/p3",
    "https://2sxc-dnn.dnndev.me/en-us/p4",
    "https://2sxc-dnn.dnndev.me/en-us/p5",
    "https://2sxc-dnn.dnndev.me/en-us/p6"
  ) `
  -Repeat 3 `
  -DelayMsBetweenRequests 150 -DelayMsBetweenRuns 500 `
  -SaveCsv -CsvPath .\results\warm-cache-x3.csv
```

### 4) Cold vs warm comparison

```powershell
# Cold phase
.\Measure-Requests.ps1 `
  -Urls @("https://2sxc-dnn.dnndev.me/en-us/", "https://2sxc-dnn.dnndev.me/en-us/p1", ...) `
  -TouchWebConfigFirst -RecycleWaitSec 5 `
  -CallKeepAlive -PostKeepAliveWaitSec 5 `
  -CleanFirst `
  -SaveCsv -CsvPath .\results\cold-once.csv

# Warm phase
.\Measure-Requests.ps1 `
  -Urls @("https://2sxc-dnn.dnndev.me/en-us/", "https://2sxc-dnn.dnndev.me/en-us/p1", ...) `
  -Repeat 3 `
  -DelayMsBetweenRequests 150 -DelayMsBetweenRuns 500 `
  -SaveCsv -CsvPath .\results\warm-x3.csv
```

### 5) Cleaning with locked files (IIS App Pool stop/start)

```powershell
.\Measure-Requests.ps1 `
  -Urls @("https://2sxc-dnn.dnndev.me/en-us/", "https://2sxc-dnn.dnndev.me/en-us/p1") `
  -AppPoolName "DefaultAppPool" `
  -StopAppPoolForCleanFirst `
  -CleanFirst `
  -CallKeepAlive -PostKeepAliveWaitSec 5 `
  -SaveCsv -CsvPath .\results\app-pool-clean.csv
```

---

## Runner Scripts

These are preconfigured examples that call `Measure-Requests.ps1`. Save them in the same folder and adjust variables at the top if needed.

* `01-Clean-And-Run-Once.ps1`
  Recycle + keepalive + clean; run once; save CSV.

* `02-Repeat5-TouchAndClean-EachRun.ps1`
  Recycle + keepalive + clean before each run; five runs; small delays; save CSV.

* `03-Warm-Cache-Run.ps1`
  Three runs; no recycle/clean; small delays; save CSV.

* `04-Cold-vs-Warm-Comparison.ps1`
  9 cold runs (recycle + clean) then 9 disk runs (recycle) and finish with 9 warm in-memory runs; saves 3 CSV files.

Optional double-click launchers:

```cmd
:: Run-Repeat5.cmd
@echo off
setlocal
powershell -NoLogo -ExecutionPolicy Bypass -File "%~dp0\02-Repeat5-TouchAndClean-EachRun.ps1"
pause
```

```cmd
:: Run-ColdWarm.cmd
@echo off
setlocal
powershell -NoLogo -ExecutionPolicy Bypass -File "%~dp0\04-Cold-vs-Warm-Comparison.ps1"
pause
```

---

## Tips

* When measuring cold performance reliably, ensure you recycle and clean just before the run. Warm-up can be helpful to ensure the site is responsive before measuring, but do not include the warm-up URL in measurements.
* If DLLs or cache files are locked, prefer the App Pool stop/start options.
* CSV analysis can be automated later to rebuild “one big table” HTML comparisons such as COLD vs DISK vs MEMORY and their ratios.

---

## Troubleshooting

* “Access denied” or “file in use” while cleaning: run PowerShell as Administrator and consider `-AppPoolName` with `-StopAppPoolForClean*`.
* Keepalive timeouts: increase `-KeepAliveTimeoutSec`, `-KeepAliveRetries`, or `-KeepAliveDelayMs`.
* Unexpected large times on first hit: ensure recycle has fully completed (`-RecycleWaitSec`) and optionally add warm-up (`-CallWarmUp`).
* CSV not created: add `-SaveCsv` and verify `-CsvPath` is writeable.

---

## License

Use at your own discretion within your projects. No warranty is provided.
