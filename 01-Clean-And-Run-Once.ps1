#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/en-us/p1",
  "https://2sxc-dnn.dnndev.me/en-us/p2",
  "https://2sxc-dnn.dnndev.me/en-us/p3",
  "https://2sxc-dnn.dnndev.me/en-us/p4",
  "https://2sxc-dnn.dnndev.me/en-us/p5",
  "https://2sxc-dnn.dnndev.me/en-us/p6"
)

$csv           = ".\results\run-once.csv"

New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null

.\Measure-Requests.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -CleanFirst `
  -Repeat 1 `
  -SaveCsv `
  -CsvPath $csv
