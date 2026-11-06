@echo off
wsl.exe -d Ubuntu-24.04 --cd "%~dp0." -- bash ./ansible %*
