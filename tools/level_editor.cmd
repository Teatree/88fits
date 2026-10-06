@echo off
rem 88fits Level Editor (pass 53): double-click to start the local server and open the editor in the browser.
rem It runs tools\level_editor\server.py from the repo root with the Python on this PC (python, else py -3).
rem Options pass through: level_editor.cmd --port 8800 --no-browser
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
echo Starting the 88fits Level Editor from "%CD%" with %PY% ...
echo (this window stays open while the editor runs; close it or press Ctrl+C to stop)
echo.
%PY% tools\level_editor\server.py %*
if errorlevel 1 (
  echo.
  echo The server stopped with an error - read the lines above.
  pause
)
endlocal
