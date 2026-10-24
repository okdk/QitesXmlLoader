@echo off
setlocal DisableDelayedExpansion
if "%~1"=="" goto usage
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Export-Folder.ps1" -Source "%~f1\." -Policy Approve
set "qitesExit=%ERRORLEVEL%"
pause
exit /b %qitesExit%
:usage
echo Drag one music folder onto this BAT. Approves supported recovery and network access; unresolved tracks are skipped.
pause
exit /b 2
