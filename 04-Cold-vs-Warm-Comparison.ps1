#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/en-us/",
  "https://2sxc-dnn.dnndev.me/en-us/p1",
  "https://2sxc-dnn.dnndev.me/en-us/p2",
  "https://2sxc-dnn.dnndev.me/en-us/p3",
  "https://2sxc-dnn.dnndev.me/en-us/p4"
)

New-Item -ItemType Directory -Force -Path ".\results" | Out-Null

# Cold run
.\Measure-Requests.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -TouchWebConfigEachRun `
  -CleanFirst `
  -CleanEachRun `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\cold-x9.csv"

# Short pause
Start-Sleep -Seconds 2

# Disk runs
.\Measure-Requests.ps1 `
  -Urls $urls `
  -TouchWebConfigEachRun `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\disk-x9.csv"

  # Short pause
Start-Sleep -Seconds 2

# Warm runs
.\Measure-Requests.ps1 `
  -Urls $urls `
  -Repeat 9 `
  -SaveCsv -CsvPath ".\results\memory-x9.csv"