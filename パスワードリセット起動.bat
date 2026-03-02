@echo off
setlocal
:: 実行するPowerShellスクリプトのファイル名（同じフォルダに置く前提）
set SCRIPT_NAME=AD_PassReset.ps1

:: 管理者として実行し直すコード
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0%SCRIPT_NAME%""' -Verb RunAs"

exit