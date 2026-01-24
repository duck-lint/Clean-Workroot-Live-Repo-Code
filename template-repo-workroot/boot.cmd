@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0%~1" %*
endlocal

# useage 
# .\boot.cmd init.ps1 (initialize)
# .\boot.cmd bootstrap.ps1 (per use)