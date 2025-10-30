#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/en-us/p1",
  "https://2sxc-dnn.dnndev.me/en-us/p2",
  "https://2sxc-dnn.dnndev.me/en-us/p3",
  "https://2sxc-dnn.dnndev.me/en-us/p4"
  "https://2sxc-dnn.dnndev.me/en-us/p5",
  "https://2sxc-dnn.dnndev.me/en-us/p6"
)

New-Item -ItemType Directory -Force -Path ".\results" | Out-Null

# Cold run
.\Measure-Requests.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -CleanFirst `
  -StopAppPoolForCleanFirst `
  -TouchWebConfigEachRun `
  -CleanEachRun `
  -StopAppPoolForCleanEachRun `
  -Repeat 1 `
  -SaveCsv -CsvPath ".\results\05-cold.csv"

# Short pause
Start-Sleep -Seconds 2

# Disk runs
.\Measure-Requests.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -TouchWebConfigEachRun `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\05-disk.csv"

  # Short pause
Start-Sleep -Seconds 2

# Warm runs
.\Measure-Requests.ps1 `
  -Urls $urls `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\05-memory.csv"