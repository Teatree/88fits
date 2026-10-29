@echo off
rem 88fits replay (pass 114): double-click to watch the newest recorded run again, on the build that recorded it.
rem   replay.cmd                 the newest recording (downloaded with tools\posthog_runs.py, or played on this PC)
rem   replay.cmd --list          every recording;  replay.cmd <file>  plays one;  --speed 4 --seek 5:00 --paused
rem How it works and what the header and the light mean: analytics\howto_replays.md
setlocal
cd /d "%~dp0.."
set "PY="
python -c "import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)" >nul 2>nul && set "PY=python"
if not defined PY py -3 -c "import sys" >nul 2>nul && set "PY=py -3"
if not defined PY (
  echo.
  echo Python 3 was not found on this PC.
  echo Install it from https://www.python.org/downloads/ and tick "Add python.exe to PATH", then run this again.
  echo.
  pause
  exit /b 1
)
if "%~1"=="" (
  %PY% toolseplay.py --latest
) else (
  %PY% toolseplay.py %*
)
if errorlevel 1 (
  echo.
  echo The replay did not start - read the lines above.
  pause
)
endlocal
