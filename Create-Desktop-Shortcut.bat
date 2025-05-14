@echo off
title Creating Desktop Shortcut
echo Creating desktop shortcut for YouTube Media Downloader...

:: Get the current directory
set "SCRIPT_DIR=%~dp0"

:: Create a shortcut on the desktop
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\CreateShortcut.vbs"
echo sLinkFile = oWS.SpecialFolders("Desktop") ^& "\YouTube Media Downloader.lnk" >> "%TEMP%\CreateShortcut.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\CreateShortcut.vbs"
echo oLink.TargetPath = "%SCRIPT_DIR%Launch-PowerShell.bat" >> "%TEMP%\CreateShortcut.vbs"
echo oLink.WorkingDirectory = "%SCRIPT_DIR%" >> "%TEMP%\CreateShortcut.vbs"
echo oLink.Description = "YouTube Media Downloader" >> "%TEMP%\CreateShortcut.vbs"
echo oLink.IconLocation = "shell32.dll,41" >> "%TEMP%\CreateShortcut.vbs"
echo oLink.WindowStyle = 1 >> "%TEMP%\CreateShortcut.vbs"
echo oLink.Save >> "%TEMP%\CreateShortcut.vbs"

:: Run the VBScript to create the shortcut
cscript //nologo "%TEMP%\CreateShortcut.vbs"

:: Delete the temporary VBScript
del "%TEMP%\CreateShortcut.vbs"

echo.
echo Desktop shortcut created successfully!
echo.
pause