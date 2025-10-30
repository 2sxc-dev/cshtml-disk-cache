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

$clean = "C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml"
$csv   = ".\results\repeat5-clean-each-XPS5.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null

.\Measure-Requests-XPS5.ps1 `
  -TouchWebConfigFirst `
  -CleanFirst `
  -StopAppPoolForCleanFirst `
  -TouchWebConfigEachRun `
  -CleanEachRun `
  -StopAppPoolForCleanEachRun `
  -Repeat 5 `
  -SaveCsv -CsvPath $csv
