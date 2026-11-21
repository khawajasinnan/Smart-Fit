@echo off
REM Start (or stop) the whole SmartFit backend without touching Windows'
REM PowerShell execution policy, which blocks .ps1 files by default:
REM
REM   run_local.bat          start all services, each in its own window
REM   run_local.bat -Stop    stop them again
REM
REM This only bypasses the policy for this one run; nothing on the PC changes.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_local.ps1" %*
