param(
    [Parameter(Mandatory=$true)]
    [string[]] $Urls,

    # Optional: folder whose contents can be deleted before tests
    [string] $CleanPath,

    # If set, clean folder before the first run
    [switch] $CleanFirst,

    # If set, clean folder before every run
    [switch] $CleanEachRun,

    # Number of times to repeat the entire set of requests
    [int] $Repeat = 1,

    # Delay between requests (milliseconds)
    [int] $DelayMsBetweenRequests = 0,

    # Delay between runs (milliseconds)
    [int] $DelayMsBetweenRuns = 0,

    # HTTP request timeout (seconds)
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

function Clear-FolderContents {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Path does not exist: $Path"
        return
    }
    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "Cleared folder contents: $Path"
    } catch {
        Write-Warning "Failed to clear folder '$Path': $($_.Exception.Message)"
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

# Optionally clean before the first run
if ($CleanFirst -and $CleanPath) {
    Clear-FolderContents -Path $CleanPath
}

for ($run = 1; $run -le $Repeat; $run++) {

    if ($run -gt 1 -and $CleanEachRun -and $CleanPath) {
        Clear-FolderContents -Path $CleanPath
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

# Print all results
Write-Host ""
Write-Host "All request results:"
$allRows | Select-Object Run, Url, Ok, Status, DurationMs, ContentLength |
    Sort-Object Run, Url |
    Format-Table -AutoSize

# Summary by URL (average, min, max)
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

Write-Host ""
Write-Host "Summary by URL:"
$summaryUrl | Format-Table -AutoSize

# Summary by run (total duration)
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

Write-Host ""
Write-Host "Summary by run:"
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
