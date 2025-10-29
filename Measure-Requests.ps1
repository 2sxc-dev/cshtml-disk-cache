param(
    [Parameter(Mandatory=$true)]
    [string[]] $Urls,

    # Paths and defaults
    [string] $CleanPath = "C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml",
    [string] $WebConfigPath = "C:\Projects\2sxc\2sxc-dnn\Website\web.config",
    [string] $KeepAliveUrl = "https://2sxc-dnn.dnndev.me/keepalive.aspx",
    [string] $WarmUpUrl = "https://2sxc-dnn.dnndev.me/",
    [string] $AppPoolName = "2sxc-dnn.dnndev.me_nvQuickSite",

    # Clean timing
    [switch] $CleanFirst,
    [switch] $CleanEachRun,

    # Touch and keepalive
    [switch] $TouchWebConfigFirst,
    [switch] $TouchWebConfigEachRun,
    [int] $RecycleWaitSec = 5,
    [switch] $CallKeepAlive = $true,
    [int] $KeepAliveTimeoutSec = 30,
    [int] $KeepAliveRetries = 3,
    [int] $KeepAliveDelayMs = 500,
    [int] $PostKeepAliveWaitSec = 5,

    # Optional IIS App Pool control (wraps delete to avoid locked files)
    [switch] $StopAppPoolForCleanFirst,
    [switch] $StopAppPoolForCleanEachRun,
    [int] $AppPoolWaitStopSec = 15,
    [int] $AppPoolWaitStartSec = 10,

    # Delete retry policy
    [int] $DeleteMaxRetries = 99,
    [int] $DeleteRetryDelayMs = 500,

    # Optional, non-measured warm-up
    [switch] $CallWarmUp = $true,
    [int] $WarmUpTimeoutSec = 30,
    [int] $WarmUpRetries = 3,
    [int] $WarmUpDelayMs = 500,
    [int] $PostWarmUpWaitMs = 30,

    # Runs and timing
    [int] $Repeat = 1,
    [int] $DelayMsBetweenRequests = 0,
    [int] $DelayMsBetweenRuns = 0,
    [int] $TimeoutSec = 60,

    # CSV
    [switch] $SaveCsv,
    [string] $CsvPath
)

# TLS
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol `
        -bor [Net.SecurityProtocolType]::Tls12 `
        -bor [Net.SecurityProtocolType]::Tls13
} catch { }

# --- IIS helpers -------------------------------------------------------------

function Get-AppCmdPath {
    $paths = @(
        "$env:windir\System32\inetsrv\appcmd.exe",
        "$env:windir\SysWOW64\inetsrv\appcmd.exe"
    )
    foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}

function Ensure-WebAdministration {
    if (Get-Module -ListAvailable -Name WebAdministration | ForEach-Object { $_ }) {
        Import-Module WebAdministration -ErrorAction SilentlyContinue | Out-Null
        return $true
    }
    return $false
}

function Stop-IISAppPool {
    param([string] $Name, [int] $WaitSec = 15)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    $usedWebAdmin = $false
    if (Ensure-WebAdministration) {
        try {
            Stop-WebAppPool -Name $Name -ErrorAction Stop
            $usedWebAdmin = $true
        } catch { }
    }
    if (-not $usedWebAdmin) {
        $appcmd = Get-AppCmdPath
        if ($appcmd) {
            & $appcmd stop apppool /apppool.name:"$Name" | Out-Null
        } else {
            Write-Warning "Cannot stop app pool '$Name': neither WebAdministration nor appcmd.exe available."
            return $false
        }
    }

    $deadline = (Get-Date).AddSeconds($WaitSec)
    while ((Get-Date) -lt $deadline) {
        $st = Get-IISAppPoolState -Name $Name
        if ($st -eq "Stopped") { return $true }
        Start-Sleep -Milliseconds 200
    }
    Write-Warning "App pool '$Name' did not reach Stopped state within $WaitSec seconds."
    return $false
}

function Start-IISAppPool {
    param([string] $Name, [int] $WaitSec = 10)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    $usedWebAdmin = $false
    if (Ensure-WebAdministration) {
        try {
            Start-WebAppPool -Name $Name -ErrorAction Stop
            $usedWebAdmin = $true
        } catch { }
    }
    if (-not $usedWebAdmin) {
        $appcmd = Get-AppCmdPath
        if ($appcmd) {
            & $appcmd start apppool /apppool.name:"$Name" | Out-Null
        } else {
            Write-Warning "Cannot start app pool '$Name': neither WebAdministration nor appcmd.exe available."
            return $false
        }
    }

    $deadline = (Get-Date).AddSeconds($WaitSec)
    while ((Get-Date) -lt $deadline) {
        $st = Get-IISAppPoolState -Name $Name
        if ($st -eq "Started") { return $true }
        Start-Sleep -Milliseconds 200
    }
    Write-Warning "App pool '$Name' did not reach Started state within $WaitSec seconds."
    return $false
}

function Get-IISAppPoolState {
    param([string] $Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    if (Ensure-WebAdministration) {
        try {
            $ap = Get-Item "IIS:\AppPools\$Name" -ErrorAction Stop
            return $ap.state
        } catch { }
    }
    # appcmd fallback
    $appcmd = Get-AppCmdPath
    if ($appcmd) {
        try {
            $out = & $appcmd list apppool /name:"$Name"
            if ($out -match "state:(\w+)") { return $Matches[1] }
        } catch { }
    }
    return $null
}

# --- File ops ----------------------------------------------------------------

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
        if ($WaitSeconds -gt 0) { Start-Sleep -Seconds $WaitSeconds }
    } catch {
        Write-Warning "Failed to touch web.config '$Path': $($_.Exception.Message)"
    }
}

function Invoke-KeepAlive {
    param([string] $Url, [int] $TimeoutSec = 30, [int] $Retries = 3, [int] $DelayMs = 500)
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
        if ($i -lt $Retries -and $DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    }
    Write-Warning "KeepAlive did not succeed after $Retries attempt(s). Continuing."
}

function Invoke-WarmUp {
    param([string] $Url, [int] $TimeoutSec = 30, [int] $Retries = 3, [int] $DelayMs = 500, [int] $PostWaitMs = 0)
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
        if ($i -lt $Retries -and $DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    }
    Write-Warning "WarmUp did not succeed after $Retries attempt(s). Continuing."
}

function Get-RemainingItemsCount {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try { return (Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count }
    catch { return -1 }
}

function Clear-AttributesIfNeeded { param([System.IO.FileSystemInfo] $Item)
    try {
        if ($Item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $Item.Attributes = $Item.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
        }
    } catch { }
}

function Clear-FolderContents {
    param([string] $Path, [int] $MaxRetries = 10, [int] $RetryDelayMs = 300)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host "Path does not exist: $Path"; return }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $items = Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
                     Sort-Object FullName -Descending
            foreach ($it in $items) {
                try {
                    Clear-AttributesIfNeeded -Item $it
                    Remove-Item -LiteralPath $it.FullName -Force -Recurse -ErrorAction Stop
                } catch { }
            }
        } catch { }

        $remaining = Get-RemainingItemsCount -Path $Path
        if ($remaining -eq 0) { Write-Host "Cleared folder contents: $Path"; return }

        if ($attempt -lt $MaxRetries) {
            Write-Host "Retry delete ($attempt/$MaxRetries). Remaining items: $remaining. Waiting ${RetryDelayMs}ms..."
            Start-Sleep -Milliseconds $RetryDelayMs
        } else {
            Write-Warning "Failed to delete all items after $MaxRetries attempt(s). Remaining items: $remaining"
        }
    }
}

# CSV prep
if ($SaveCsv -and [string]::IsNullOrWhiteSpace($CsvPath)) {
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $CsvPath = Join-Path -Path (Get-Location) -ChildPath "measure-requests-$stamp.csv"
}

# URLs
$Urls = $Urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
if ($Urls.Count -eq 0) { throw "No URLs provided." }

$allRows = New-Object System.Collections.Generic.List[object]

# --- INITIAL PREP: stop app pool (optional) -> touch/keepalive -> delete -> start app pool (optional) -> keepalive+wait -> warmup ---

# If StopAppPoolForCleanFirst is set, we stop before delete; we do not call KeepAlive until after we start again.
if ($StopAppPoolForCleanFirst -and $AppPoolName) {
    [void](Stop-IISAppPool -Name $AppPoolName -WaitSec $AppPoolWaitStopSec)
}

if ($TouchWebConfigFirst -and $WebConfigPath -and -not ($StopAppPoolForCleanFirst -and $AppPoolName)) {
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

if ($StopAppPoolForCleanFirst -and $AppPoolName) {
    [void](Start-IISAppPool -Name $AppPoolName -WaitSec $AppPoolWaitStartSec)
    # Now do KeepAlive after we are started
    if ($CallKeepAlive -and $KeepAliveUrl) {
        Invoke-KeepAlive -Url $KeepAliveUrl -TimeoutSec $KeepAliveTimeoutSec -Retries $KeepAliveRetries -DelayMs $KeepAliveDelayMs
        if ($PostKeepAliveWaitSec -gt 0) {
            Write-Host "Waiting $PostKeepAliveWaitSec seconds after KeepAlive..."
            Start-Sleep -Seconds $PostKeepAliveWaitSec
        }
    }
}

if ($CallWarmUp -and $WarmUpUrl) {
    Invoke-WarmUp -Url $WarmUpUrl -TimeoutSec $WarmUpTimeoutSec -Retries $WarmUpRetries -DelayMs $WarmUpDelayMs -PostWaitMs $PostWarmUpWaitMs
}

# --- RUNS ---

for ($run = 1; $run -le $Repeat; $run++) {

    if ($run -gt 1) {
        if ($StopAppPoolForCleanEachRun -and $AppPoolName) {
            [void](Stop-IISAppPool -Name $AppPoolName -WaitSec $AppPoolWaitStopSec)
        }

        if ($TouchWebConfigEachRun -and $WebConfigPath -and -not ($StopAppPoolForCleanEachRun -and $AppPoolName)) {
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

        if ($StopAppPoolForCleanEachRun -and $AppPoolName) {
            [void](Start-IISAppPool -Name $AppPoolName -WaitSec $AppPoolWaitStartSec)
            if ($CallKeepAlive -and $KeepAliveUrl) {
                Invoke-KeepAlive -Url $KeepAliveUrl -TimeoutSec $KeepAliveTimeoutSec -Retries $KeepAliveRetries -DelayMs $KeepAliveDelayMs
                if ($PostKeepAliveWaitSec -gt 0) {
                    Write-Host "Waiting $PostKeepAliveWaitSec seconds after KeepAlive..."
                    Start-Sleep -Seconds $PostKeepAliveWaitSec
                }
            }
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
        } catch {
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

        if ($DelayMsBetweenRequests -gt 0) { Start-Sleep -Milliseconds $DelayMsBetweenRequests }
    }

    $runStopwatch.Stop()
    Write-Host ("Total time for run #{0}: {1} ms" -f $run, [int]$runStopwatch.Elapsed.TotalMilliseconds)

    if ($run -lt $Repeat -and $DelayMsBetweenRuns -gt 0) {
        Start-Sleep -Milliseconds $DelayMsBetweenRuns
    }
}

# --- REPORTING ---

Write-Host ""
Write-Host "All request results:"
$allRows | Select-Object Run, Url, Ok, Status, DurationMs, ContentLength |
    Sort-Object Run, Url | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary by URL:"
$summaryUrl = $allRows | Group-Object Url | ForEach-Object {
    $d = $_.Group.DurationMs
    [PSCustomObject]@{
        Url        = $_.Name
        Count      = $_.Group.Count
        AvgMs      = [math]::Round(($d | Measure-Object -Average).Average, 2)
        MinMs      = ($d | Measure-Object -Minimum).Minimum
        MaxMs      = ($d | Measure-Object -Maximum).Maximum
        SuccessPct = [math]::Round(100.0 * ($_.Group | Where-Object {$_.Ok}).Count / $_.Group.Count, 1)
    }
}
$summaryUrl | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary by run:"
$summaryRun = $allRows | Group-Object Run | ForEach-Object {
    [PSCustomObject]@{
        Run     = $_.Name
        TotalMs = ($_.Group | Measure-Object DurationMs -Sum).Sum
        Success = ($_.Group | Where-Object {$_.Ok}).Count
        Count   = $_.Group.Count
    }
}
$summaryRun | Format-Table -AutoSize

if ($SaveCsv) {
    try {
        $allRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "CSV saved to: $CsvPath"
    } catch {
        Write-Warning "Failed to save CSV: $($_.Exception.Message)"
    }
}
