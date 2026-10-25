@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Benchmark.ps1"
set "BENCH_EXIT=%ERRORLEVEL%"
echo.
echo Nhan phim bat ky de dong cua so...
pause >nul
exit /b %BENCH_EXIT%
