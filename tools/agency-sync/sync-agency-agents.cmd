@echo off
setlocal
powershell.exe -ExecutionPolicy Bypass -File "%~dp0sync-agency-agents.ps1" %*
exit /b %ERRORLEVEL%
