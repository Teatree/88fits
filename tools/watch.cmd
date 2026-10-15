@echo off
rem 88fits Watch (pass 80): double-click to watch the bot play one run of the real game in a PC window: the
rem Drifter, a quarter board, a random seed, the default bot. Options pass through, e.g.
rem   watch.cmd --hero calavera --board half --speed 4 --bot skill=0.6
rem (python tools\watch.py --help lists them all). The window opens a few seconds after the snapshot is refreshed.
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
echo Starting the 88fits Watch from "%CD%" with %PY% ...
%PY% tools\watch.py --hero drifter --board quarter --seed random %*
if errorlevel 1 (
  echo.
  echo The Watch did not start - read the lines above.
  pause
)
endlocal
