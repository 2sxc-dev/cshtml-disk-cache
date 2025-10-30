#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p1",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p2",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p3",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p4"
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p5",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p6"
)

New-Item -ItemType Directory -Force -Path ".\results" | Out-Null

# Cold run
.\Measure-Requests-XPS5.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -CleanFirst `
  -StopAppPoolForCleanFirst `
  -TouchWebConfigEachRun `
  -CleanEachRun `
  -StopAppPoolForCleanEachRun `
  -Repeat 1 `
  -SaveCsv -CsvPath ".\results\05-cold-XPS5.csv"

# Short pause
Start-Sleep -Seconds 2

# Disk runs
.\Measure-Requests-XPS5.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -TouchWebConfigEachRun `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\05-disk-XPS5.csv"

  # Short pause
Start-Sleep -Seconds 2

# # Warm runs
# .\Measure-Requests-XPS5.ps1 `
#   -Urls $urls `
#   -Repeat 9 `
#   -SaveCsv -CsvPath ".\results\05-memory-XPS5.csv"