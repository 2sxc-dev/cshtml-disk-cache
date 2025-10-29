#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/en-us/",
  "https://2sxc-dnn.dnndev.me/en-us/p1",
  "https://2sxc-dnn.dnndev.me/en-us/p2",
  "https://2sxc-dnn.dnndev.me/en-us/p3",
  "https://2sxc-dnn.dnndev.me/en-us/p4",
  "https://2sxc-dnn.dnndev.me/en-us/p5",
  "https://2sxc-dnn.dnndev.me/en-us/p6"
)

$clean = "C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml"
$csv   = ".\results\repeat5-clean-each.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null

.\Measure-Requests.ps1 `
  -TouchWebConfigFirst `
  -CleanFirst `
  -StopAppPoolForCleanFirst `
  -TouchWebConfigEachRun `
  -CleanEachRun `
  -StopAppPoolForCleanEachRun `
  -Repeat 5 `
  -SaveCsv -CsvPath $csv
