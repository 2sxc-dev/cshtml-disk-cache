#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/en-us/",
  "https://2sxc-dnn.dnndev.me/en-us/p1",
  "https://2sxc-dnn.dnndev.me/en-us/p2",
  "https://2sxc-dnn.dnndev.me/en-us/p3",
  "https://2sxc-dnn.dnndev.me/en-us/p4"
)

$clean = "C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml"
New-Item -ItemType Directory -Force -Path ".\results" | Out-Null

# Cold run
.\Measure-Requests.ps1 `
  -Urls $urls `
  -CleanPath $clean `
  -CleanFirst `
  -Repeat 1 `
  -TimeoutSec 60 `
  -SaveCsv -CsvPath ".\results\cold-once.csv"

# Short pause
Start-Sleep -Seconds 2

# Warm runs
.\Measure-Requests.ps1 `
  -Urls $urls `
  -Repeat 3 `
  -DelayMsBetweenRequests 150 `
  -DelayMsBetweenRuns 500 `
  -TimeoutSec 60 `
  -SaveCsv -CsvPath ".\results\warm-x3.csv"
