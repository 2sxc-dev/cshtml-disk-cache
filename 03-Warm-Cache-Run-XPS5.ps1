#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p1",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p2",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p3",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p4",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p5",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p6"
)

$csv = ".\results\warm-cache-x3-XPS5.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null

.\Measure-Requests-XPS5.ps1 `
  -Urls $urls `
  -Repeat 3 `
  -DelayMsBetweenRequests 150 `
  -DelayMsBetweenRuns 500 `
  -TimeoutSec 60 `
  -SaveCsv -CsvPath $csv
