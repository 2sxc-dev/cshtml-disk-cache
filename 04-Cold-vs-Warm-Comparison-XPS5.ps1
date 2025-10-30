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
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\cold-x9-XPS5.csv"

# Short pause
Start-Sleep -Seconds 2

# Disk runs
.\Measure-Requests-XPS5.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -TouchWebConfigEachRun `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\disk-x9-XPS5.csv"

  # Short pause
Start-Sleep -Seconds 2

# Warm runs
.\Measure-Requests-XPS5.ps1 `
  -Urls $urls `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\memory-x9-XPS5.csv"