@echo off
setlocal DisableDelayedExpansion
if "%~1"=="" goto usage
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Export-Folder.ps1" -Source "%~f1\." -Policy Ignore
set "qitesExit=%ERRORLEVEL%"
pause
exit /b %qitesExit%
:usage
echo Drag one music folder onto this BAT. Unavailable tracks are skipped; unknown network access is rejected.
pause
exit /b 2
