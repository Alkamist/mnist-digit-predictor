@echo off
setlocal enabledelayedexpansion

REM Build the JSON payload with 784 zeros
set "zeros="
for /L %%i in (1,1,783) do set "zeros=!zeros!0,"
set "PAYLOAD={\"image\":[!zeros!0]}"

REM Execute the POST request using curl
curl.exe -X POST http://localhost/predict ^
         -H "Content-Type: application/json" ^
         -d "!PAYLOAD!"

pause