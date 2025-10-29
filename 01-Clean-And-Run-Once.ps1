#Requires -Version 5.1
$urls = @(
  "https://2sxc-dnn.dnndev.me/keepalive.aspx",
  "https://2sxc-dnn.dnndev.me/en-us/",
  "https://2sxc-dnn.dnndev.me/en-us/p1",
  "https://2sxc-dnn.dnndev.me/en-us/p2",
  "https://2sxc-dnn.dnndev.me/en-us/p3",
  "https://2sxc-dnn.dnndev.me/en-us/p4",
  "https://2sxc-dnn.dnndev.me/en-us/p5",
  "https://2sxc-dnn.dnndev.me/en-us/p6"
)

$cleanPath     = "C:\Projects\2sxc\2sxc-dnn\Website\App_Data\2sxc.bin\cshtml"
$webConfigPath = "C:\Projects\2sxc\2sxc-dnn\Website\web.config"
$csv           = ".\results\run-once.csv"

New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null

.\Measure-Requests.ps1 `
  -Urls $urls `
  -WebConfigPath $webConfigPath `
  -TouchWebConfigFirst `
  -RecycleWaitSec 30 `
  -CallKeepAlive `
  -KeepAliveUrl "https://2sxc-dnn.dnndev.me/keepalive.aspx" `
  -CleanFirst `
  -CleanPath $cleanPath `
  -Repeat 1 `
  -TimeoutSec 60 `
  -SaveCsv -CsvPath $csv
