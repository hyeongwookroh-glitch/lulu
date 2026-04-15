@echo off
cd /d "%~dp0"

:loop
claude --model opus --effort max --dangerously-skip-permissions --strict-mcp-config --mcp-config .mcp-lulu.json --dangerously-load-development-channels server:lulu
echo [%date% %time%] Lulu exited (code: %ERRORLEVEL%), restarting in 3s...
timeout /t 3 >nul
goto loop
