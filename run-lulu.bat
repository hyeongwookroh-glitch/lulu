@echo off
cd /d "%~dp0"

powershell -NoProfile -Command "if (Get-WmiObject Win32_Process -Filter \"name='claude.exe'\" | Where-Object { $_.CommandLine -like '*server:lulu*' }) { exit 0 } else { exit 1 }" >NUL 2>&1
if not errorlevel 1 (
    echo [Lulu] Already running. Exiting.
    timeout /t 3 >nul
    exit /b 1
)

:loop
claude --model opus --effort max --dangerously-skip-permissions --strict-mcp-config --mcp-config .mcp-lulu.json --dangerously-load-development-channels server:lulu
echo [%date% %time%] Lulu exited (code: %ERRORLEVEL%), restarting in 3s...
timeout /t 3 >nul
goto loop
