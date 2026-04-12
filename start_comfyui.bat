@echo off
:: ============================================================
:: ComfyUI Toolkit — start_comfyui.bat
:: Double-click to launch. Opens a PowerShell window with
:: full color and Unicode support.
:: ============================================================
:: 'start' opens PowerShell as an independent process and
:: immediately closes this cmd window — only one window
:: appears on the taskbar.
:: ============================================================

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0comfyui.ps1"
exit /b 0
