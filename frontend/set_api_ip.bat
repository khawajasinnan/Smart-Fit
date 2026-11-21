@echo off
REM Point the app at this PC's current LAN address (Wi-Fi hands out a new one
REM now and then, and then every request fails with "connection timeout").
REM
REM   set_api_ip.bat            detect this PC's IP and write it into env\dev.json
REM   set_api_ip.bat 10.0.0.5   or set one by hand
REM
REM Windows blocks .ps1 files by default, so this runs it with a one-off bypass.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set_api_ip.ps1" %*
