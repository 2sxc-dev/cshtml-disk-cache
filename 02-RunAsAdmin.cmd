@cd %~dp0
powershell.exe -ExecutionPolicy ByPass -File %~dp002-Repeat5-CleanEach.ps1 -Path %~dp0
@pause