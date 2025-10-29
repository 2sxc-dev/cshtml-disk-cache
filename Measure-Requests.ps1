param(
    [Parameter(Mandatory=$true)]
    [string[]] $Urls,

    # Folder koji se može isprazniti (samo sadržaj)
    [string] $CleanPath,

    # Ako je zadano, briše sadržaj CleanPath prije prvog pokretanja
    [switch] $CleanFirst,

    # Ako je zadano, briše sadržaj CleanPath prije SVAKOG ponavljanja
    [switch] $CleanEachRun,

    # Koliko puta ponoviti cijeli niz URL-ova
    [int] $Repeat = 1,

    # Pauza između pojedinih requestova (u milisekundama)
    [int] $DelayMsBetweenRequests = 0,

    # Pauza između ponavljanja seta (u milisekundama)
    [int] $DelayMsBetweenRuns = 0,

    # Timeout za HTTP request (sekunde)
    [int] $TimeoutSec = 60,

    # Spremi CSV log?
    [switch] $SaveCsv,

    # Put do CSV-a (ako nije zadano, kreira timestampirani u isti folder gdje se pokreće)
    [string] $CsvPath
)

# Osiguraj UTF-8 output da se ispravno prikažu dijakritici i emoji
try {
    if ([Console]::OutputEncoding.CodePage -ne 65001) {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    if ($PSVersionTable.PSVersion.Major -lt 6 -and [Console]::InputEncoding.CodePage -ne 65001) {
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    }
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# --- Helper: osiguraj TLS 1.2+ na starijim PowerShell verzijama ---
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
        Write-Host "⚠️  Ne postoji putanja: $Path"
        return
    }
    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "🧹 Očišćen sadržaj: $Path"
    } catch {
        Write-Warning "Nisam uspio obrisati sadržaj '$Path': $($_.Exception.Message)"
    }
}

# Priprema CSV-a
if ($SaveCsv -and [string]::IsNullOrWhiteSpace($CsvPath)) {
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $CsvPath = Join-Path -Path (Get-Location) -ChildPath "measure-requests-$stamp.csv"
}

# Validacija URL-ova
$Urls = $Urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
if ($Urls.Count -eq 0) { throw "Niste zadali niti jedan URL." }

$allRows = New-Object System.Collections.Generic.List[object]

# Po želji očisti prije prvog pokretanja
if ($CleanFirst -and $CleanPath) {
    Clear-FolderContents -Path $CleanPath
}

for ($run = 1; $run -le $Repeat; $run++) {

    if ($run -gt 1 -and $CleanEachRun -and $CleanPath) {
        Clear-FolderContents -Path $CleanPath
    }

    Write-Host ""
    Write-Host "▶️  Pokretanje #$run od $Repeat" -ForegroundColor Cyan

    $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($u in $Urls) {
        $reqSw = [System.Diagnostics.Stopwatch]::StartNew()

        $status = ""
        $ok = $false
        $contentLen = $null
        $errorMsg = $null

        try {
            # PS5 ima UseBasicParsing, PS7 ga ignorira – ok je zadati
            $resp = Invoke-WebRequest -Uri $u -TimeoutSec $TimeoutSec -UseBasicParsing
            $reqSw.Stop()

            # Pokušaj izvući status i duljinu sadržaja (ako postoji)
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
            # Ako je dostupno, pokušaj dohvatiti response status
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
    Write-Host ("⏱️  Ukupno vrijeme za run #{0}: {1} ms" -f $run, [int]$runStopwatch.Elapsed.TotalMilliseconds)

    if ($run -lt $Repeat -and $DelayMsBetweenRuns -gt 0) {
        Start-Sleep -Milliseconds $DelayMsBetweenRuns
    }
}

# Ispis detalja
Write-Host ""
Write-Host "Rezultati (svi requestovi):" -ForegroundColor Green
$allRows | Select-Object Run, Url, Ok, Status, DurationMs, ContentLength |
    Sort-Object Run, Url |
    Format-Table -AutoSize

# Sažetak po URL-u (prosjek, min, max)
$summaryUrl =
    $allRows |
    Group-Object Url |
    ForEach-Object {
        $okDurations = $_.Group.DurationMs
        [PSCustomObject]@{
            Url        = $_.Name
            Count      = $_.Group.Count
            AvgMs      = [math]::Round( ($okDurations | Measure-Object -Average).Average, 2)
            MinMs      = ($okDurations | Measure-Object -Minimum).Minimum
            MaxMs      = ($okDurations | Measure-Object -Maximum).Maximum
            SuccessPct = [math]::Round( (100.0 * ($_.Group | Where-Object {$_.Ok}).Count / $_.Group.Count), 1)
        }
    } | Sort-Object Url

Write-Host ""
Write-Host "Sažetak po URL-u:" -ForegroundColor Green
$summaryUrl | Format-Table -AutoSize

# Sažetak po run-u (ukupno vrijeme po pokretanju)
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
Write-Host "Sažetak po run-u:" -ForegroundColor Green
$summaryRun | Format-Table -AutoSize

# Spremi CSV ako je traženo
if ($SaveCsv) {
    try {
        $allRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "💾 CSV spremljen: $CsvPath" -ForegroundColor Yellow
    } catch {
        Write-Warning "Nisam uspio spremiti CSV: $($_.Exception.Message)"
    }
}
