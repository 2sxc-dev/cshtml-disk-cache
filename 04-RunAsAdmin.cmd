@cd %~dp0
powershell.exe -ExecutionPolicy ByPass -File %~dp004-Cold-vs-Warm-Comparison.ps1 -Path %~dp0
@pause