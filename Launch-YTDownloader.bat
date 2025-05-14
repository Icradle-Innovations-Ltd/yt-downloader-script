@echo off
title YouTube Media Downloader
color 0A
echo ===================================================
echo        YouTube Media Downloader Launcher
echo ===================================================
echo.
echo Starting the downloader...
echo.
echo If a security warning appears, select "Run" to continue.
echo.

:: Run the PowerShell script with execution policy bypass
powershell.exe -ExecutionPolicy Bypass -File "%~dp0YT-MediaFetcher-v7.ps1"

:: If the script exits with an error, pause to show the error message
if %errorlevel% neq 0 (
    echo.
    echo An error occurred while running the script.
    echo Please check the log file for details.
    echo.
    pause
) else (
    echo.
    echo Download completed successfully!
    echo.
    timeout /t 3 >nul
)