@cd %~dp0
powershell.exe -ExecutionPolicy ByPass -File %~dp001-Clean-And-Run-Once.ps1 -Path %~dp0
@pause