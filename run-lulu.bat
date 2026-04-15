@echo off
cd /d "%~dp0"

tasklist /FI "IMAGENAME eq claude.exe" 2>NUL | find /I "claude.exe" >NUL
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
