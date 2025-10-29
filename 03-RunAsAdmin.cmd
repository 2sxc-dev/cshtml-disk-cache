@cd %~dp0
powershell.exe -ExecutionPolicy ByPass -File %~dp003-Warm-Cache-Run.ps1 -Path %~dp0
@pause