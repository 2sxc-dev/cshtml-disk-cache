#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p1",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p2",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p3",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p4",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p5",
  "https://2sxc-dnn.dnndev.me/cshtml-disk-cache/p6"
)

$csv           = ".\results\run-once-XPS5.csv"

New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null

.\Measure-Requests-XPS5.ps1 `
  -Urls $urls `
  -TouchWebConfigFirst `
  -CleanFirst `
  -StopAppPoolForCleanFirst `
  -Repeat 1 `
  -SaveCsv `
  -CsvPath $csv
