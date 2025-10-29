param(
    [Parameter(Mandatory=$true)]
    [string[]] $Urls,

    # Optional: folder whose contents can be deleted before tests
    [string] $CleanPath = "C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml",

    # If set, clean folder before the first run (after optional touch+keepalive and before warmup)
    [switch] $CleanFirst,

    # If set, clean folder before every run (after optional touch+keepalive and before warmup)
    [switch] $CleanEachRun,

    # Optional: path to web.config to touch for recycling the site/app
    [string] $WebConfigPath = "C:\Projects\2sxc\2sxc-dnn\Website\web.config",

    # If set, touch web.config before the first run (recycle IIS/DNN)
    [switch] $TouchWebConfigFirst,

    # If set, touch web.config before every run (recycle IIS/DNN)
    [switch] $TouchWebConfigEachRun,

    # Seconds to wait after touching web.config to allow recycle to begin
    [int] $RecycleWaitSec = 15,

    # Call a keepalive endpoint after touching web.config and before cleaning
    [switch] $CallKeepAlive = $true,

    # KeepAlive endpoint URL
    [string] $KeepAliveUrl = "https://2sxc-dnn.dnndev.me/en-us/",

    # KeepAlive HTTP timeout (seconds)
    [int] $KeepAliveTimeoutSec = 30,

    # KeepAlive retries and delay
    [int] $KeepAliveRetries = 10,
    [int] $KeepAliveDelayMs = 500,

    # Wait after keepalive (before cleaning)
    [int] $PostKeepAliveWaitSec = 15,

    # Delete folder contents retry policy
    [int] $DeleteMaxRetries = 99,
    [int] $DeleteRetryDelayMs = 300,

    # Optional, non-measured warmup request that runs before measured URLs
    # Runs after touch+keepalive+delete, both before first run and before each run (if enabled)
    [switch] $CallWarmUp = $true,
    [string] $WarmUpUrl = "https://2sxc-dnn.dnndev.me/en-us/",
    [int] $WarmUpTimeoutSec = 30,
    [int] $WarmUpRetries = 10,
    [int] $WarmUpDelayMs = 500,
    [int] $PostWarmUpWaitMs = 10000,

    # Number of times to repeat the entire set of requests
    [int] $Repeat = 1,

    # Delay between measured requests (milliseconds)
    [int] $DelayMsBetweenRequests = 0,

    # Delay between runs (milliseconds)
    [int] $DelayMsBetweenRuns = 0,

    # HTTP request timeout (seconds) for measured requests
    [int] $TimeoutSec = 60,

    # Save results to a CSV file
    [switch] $SaveCsv,

    # CSV file path (optional; default = timestamped file in current folder)
    [string] $CsvPath
)

# Ensure TLS 1.2+ support
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12 `
        -bor [Net.SecurityProtocolType]::Tls13
} catch { }

function Touch-File {
    param([string] $Path, [int] $WaitSeconds = 0)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "web.config not found: $Path"
        return
    }
    try {
        [System.IO.File]::SetLastWriteTimeUtc($Path, [DateTime]::UtcNow)
        Write-Host "Touched web.config: $Path"
        if ($WaitSeconds -gt 0) {
            Start-Sleep -Seconds $WaitSeconds
        }
    } catch {
        Write-Warning "Failed to touch web.config '$Path': $($_.Exception.Message)"
    }
}

function Invoke-KeepAlive {
    param(
        [string] $Url,
        [int] $TimeoutSec = 30,
        [int] $Retries = 3,
        [int] $DelayMs = 500
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return }

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
            $code = $resp.StatusCode
            Write-Host "KeepAlive attempt $i/$Retries returned HTTP $code"
            if ($code -ge 200 -and $code -lt 500) { return }
        } catch {
            Write-Host "KeepAlive attempt $i/$Retries failed: $($_.Exception.Message)"
        }
        if ($i -lt $Retries -and $DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    Write-Warning "KeepAlive did not succeed after $Retries attempt(s). Continuing."
}

function Invoke-WarmUp {
    param(
        [string] $Url,
        [int] $TimeoutSec = 30,
        [int] $Retries = 3,
        [int] $DelayMs = 500,
        [int] $PostWaitMs = 0
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return }

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
            $code = $resp.StatusCode
            Write-Host "WarmUp attempt $i/$Retries returned HTTP $code"
            if ($code -ge 200 -and $code -lt 500) {
                if ($PostWaitMs -gt 0) { Start-Sleep -Milliseconds $PostWaitMs }
                return
            }
        } catch {
            Write-Host "WarmUp attempt $i/$Retries failed: $($_.Exception.Message)"
        }
        if ($i -lt $Retries -and $DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    Write-Warning "WarmUp did not succeed after $Retries attempt(s). Continuing."
}

function Get-RemainingItemsCount {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        return (Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
    } catch {
        return -1
    }
}

function Clear-AttributesIfNeeded {
    param([System.IO.FileSystemInfo] $Item)
    try {
        if ($Item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $Item.Attributes = $Item.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
        }
    } catch { }
}

function Clear-FolderContents {
    param(
        [string] $Path,
        [int] $MaxRetries = 10,
        [int] $RetryDelayMs = 300
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Path does not exist: $Path"
        return
    }

    $offlinePath = $null
    $offlineCreated = $false
    $offlineDir = $null

    if (-not [string]::IsNullOrWhiteSpace($script:WebConfigPath)) {
        try {
            $offlineDir = Split-Path -Path $script:WebConfigPath -Parent
        } catch { $offlineDir = $null }
    }
    # if ([string]::IsNullOrWhiteSpace($offlineDir)) {
    #     $offlineDir = Split-Path -Path $Path -Parent
    # }

    if (-not [string]::IsNullOrWhiteSpace($offlineDir)) {
        $offlinePath = Join-Path -Path $offlineDir -ChildPath "app_offline.htm"
        try {
            "Application offline for maintenance." | Set-Content -Path $offlinePath -Encoding UTF8 -Force
            $offlineCreated = $true
        } catch {
            Write-Warning "Failed to create appoffline file '$offlinePath': $($_.Exception.Message)"
        }
    }

    try {
        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                $items = Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
                         Sort-Object FullName -Descending
                foreach ($it in $items) {
                    try {
                        Clear-AttributesIfNeeded -Item $it
                        Remove-Item -LiteralPath $it.FullName -Force -Recurse -ErrorAction Stop
                    } catch {
                        # Let retry loop handle locked items
                    }
                }
            } catch { }

            $remaining = Get-RemainingItemsCount -Path $Path
            if ($remaining -eq 0) {
                Write-Host "Cleared folder contents: $Path"
                return
            }

            if ($attempt -lt $MaxRetries) {
                Write-Host "Retry delete ($attempt/$MaxRetries). Remaining items: $remaining. Waiting ${RetryDelayMs}ms..."
                Start-Sleep -Milliseconds $RetryDelayMs
            } else {
                Write-Warning "Failed to delete all items after $MaxRetries attempt(s). Remaining items: $remaining"
            }
        }
    }
    finally {
        if ($offlineCreated -and $offlinePath -and (Test-Path -LiteralPath $offlinePath)) {
            try {
                Remove-Item -LiteralPath $offlinePath -Force -ErrorAction Stop
            } catch {
                Write-Warning "Failed to delete appoffline file '$offlinePath': $($_.Exception.Message)"
            }
        }
    }
}

# Prepare CSV path if saving
if ($SaveCsv -and [string]::IsNullOrWhiteSpace($CsvPath)) {
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $CsvPath = Join-Path -Path (Get-Location) -ChildPath "measure-requests-$stamp.csv"
}

# Validate URLs
$Urls = $Urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
if ($Urls.Count -eq 0) { throw "No URLs provided." }

$allRows = New-Object System.Collections.Generic.List[object]

# ----- INITIAL PREP: touch -> keepalive -> wait -> delete -> warmup -----
if ($TouchWebConfigFirst -and $WebConfigPath) {
    Touch-File -Path $WebConfigPath -WaitSeconds $RecycleWaitSec
    if ($CallKeepAlive -and $KeepAliveUrl) {
        Invoke-KeepAlive -Url $KeepAliveUrl -TimeoutSec $KeepAliveTimeoutSec -Retries $KeepAliveRetries -DelayMs $KeepAliveDelayMs
        if ($PostKeepAliveWaitSec -gt 0) {
            Write-Host "Waiting $PostKeepAliveWaitSec seconds after KeepAlive..."
            Start-Sleep -Seconds $PostKeepAliveWaitSec
        }
    }
}
if ($CleanFirst -and $CleanPath) {
    Clear-FolderContents -Path $CleanPath -MaxRetries $DeleteMaxRetries -RetryDelayMs $DeleteRetryDelayMs
}
if ($CallWarmUp -and $WarmUpUrl) {
    Invoke-WarmUp -Url $WarmUpUrl -TimeoutSec $WarmUpTimeoutSec -Retries $WarmUpRetries -DelayMs $WarmUpDelayMs -PostWaitMs $PostWarmUpWaitMs
}

# ----- RUNS -----
for ($run = 1; $run -le $Repeat; $run++) {

    if ($run -gt 1) {
        if ($TouchWebConfigEachRun -and $WebConfigPath) {
            Touch-File -Path $WebConfigPath -WaitSeconds $RecycleWaitSec
            if ($CallKeepAlive -and $KeepAliveUrl) {
                Invoke-KeepAlive -Url $KeepAliveUrl -TimeoutSec $KeepAliveTimeoutSec -Retries $KeepAliveRetries -DelayMs $KeepAliveDelayMs
                if ($PostKeepAliveWaitSec -gt 0) {
                    Write-Host "Waiting $PostKeepAliveWaitSec seconds after KeepAlive..."
                    Start-Sleep -Seconds $PostKeepAliveWaitSec
                }
            }
        }
        if ($CleanEachRun -and $CleanPath) {
            Clear-FolderContents -Path $CleanPath -MaxRetries $DeleteMaxRetries -RetryDelayMs $DeleteRetryDelayMs
        }
        if ($CallWarmUp -and $WarmUpUrl) {
            Invoke-WarmUp -Url $WarmUpUrl -TimeoutSec $WarmUpTimeoutSec -Retries $WarmUpRetries -DelayMs $WarmUpDelayMs -PostWaitMs $PostWarmUpWaitMs
        }
    }

    Write-Host ""
    Write-Host "Run #$run of $Repeat"

    $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($u in $Urls) {
        $reqSw = [System.Diagnostics.Stopwatch]::StartNew()

        $status = ""
        $ok = $false
        $contentLen = $null
        $errorMsg = $null

        try {
            $resp = Invoke-WebRequest -Uri $u -TimeoutSec $TimeoutSec -UseBasicParsing
            $reqSw.Stop()

            try { $status = ($resp.StatusCode) } catch { $status = "" }
            try {
                if ($resp.RawContentLength) { $contentLen = $resp.RawContentLength }
                elseif ($resp.Content) { $contentLen = ($resp.Content | Out-String).Length }
            } catch { $contentLen = $null }

            $ok = $true
        }
        catch {
            $reqSw.Stop()
            $errorMsg = $_.Exception.Message
            try {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $status = [int]$_.Exception.Response.StatusCode
                } else { $status = "ERR" }
            } catch { $status = "ERR" }
        }

        $row = [PSCustomObject]@{
            Timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Run           = $run
            Url           = $u
            Ok            = $ok
            Status        = $status
            DurationMs    = [int]$reqSw.Elapsed.TotalMilliseconds
            ContentLength = $contentLen
            Error         = $errorMsg
        }

        $allRows.Add($row) | Out-Null

        $statusTxt = if ($ok) { "OK" } else { "FAIL" }
        Write-Host (" - {0} [{1}] {2} ms" -f $u, $statusTxt, $row.DurationMs)

        if ($DelayMsBetweenRequests -gt 0) {
            Start-Sleep -Milliseconds $DelayMsBetweenRequests
        }
    }

    $runStopwatch.Stop()
    Write-Host ("Total time for run #{0}: {1} ms" -f $run, [int]$runStopwatch.Elapsed.TotalMilliseconds)

    if ($run -lt $Repeat -and $DelayMsBetweenRuns -gt 0) {
        Start-Sleep -Milliseconds $DelayMsBetweenRuns
    }
}

# ----- REPORTING -----
Write-Host ""
Write-Host "All request results:"
$allRows | Select-Object Run, Url, Ok, Status, DurationMs, ContentLength |
    Sort-Object Run, Url |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Summary by URL:"
$summaryUrl =
    $allRows |
    Group-Object Url |
    ForEach-Object {
        $durations = $_.Group.DurationMs
        [PSCustomObject]@{
            Url        = $_.Name
            Count      = $_.Group.Count
            AvgMs      = [math]::Round( ($durations | Measure-Object -Average).Average, 2)
            MinMs      = ($durations | Measure-Object -Minimum).Minimum
            MaxMs      = ($durations | Measure-Object -Maximum).Maximum
            SuccessPct = [math]::Round( (100.0 * ($_.Group | Where-Object {$_.Ok}).Count / $_.Group.Count), 1)
        }
    } | Sort-Object Url
$summaryUrl | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary by run:"
$summaryRun =
    $allRows |
    Group-Object Run |
    ForEach-Object {
        [PSCustomObject]@{
            Run     = $_.Name
            TotalMs = ($_.Group | Measure-Object DurationMs -Sum).Sum
            Success = ($_.Group | Where-Object {$_.Ok}).Count
            Count   = $_.Group.Count
        }
    } | Sort-Object Run
$summaryRun | Format-Table -AutoSize

# Save CSV if requested
if ($SaveCsv) {
    try {
        $allRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "CSV saved to: $CsvPath"
    } catch {
        Write-Warning "Failed to save CSV: $($_.Exception.Message)"
    }
}
