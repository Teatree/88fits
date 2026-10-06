@echo off
rem 88fits (pass 53): run tools/ship.sh (checks, signed APK, install on the phone, copy to Google Drive) from a
rem double-click or a cmd prompt, through Git Bash. Arguments pass through: ship.cmd --quick --no-install
setlocal
cd /d "%~dp0.."
set "BASH="
if exist "C:\Program Files\Git\bin\bash.exe" set "BASH=C:\Program Files\Git\bin\bash.exe"
if not defined BASH if exist "C:\Program Files\Git\usr\bin\bash.exe" set "BASH=C:\Program Files\Git\usr\bin\bash.exe"
if not defined BASH for %%B in (bash.exe) do if not "%%~$PATH:B"=="" set "BASH=%%~$PATH:B"
if not defined BASH (
  echo.
  echo Git Bash was not found: looked in "C:\Program Files\Git\bin", "C:\Program Files\Git\usr\bin" and on PATH.
  echo Install Git for Windows from https://git-scm.com/download/win and run this again.
  echo.
  pause
  exit /b 1
)
echo Running tools/ship.sh %* from "%CD%" with "%BASH%" ...
echo.
"%BASH%" -lc "cd \"$(cygpath -u \"%CD%\")\" && bash tools/ship.sh %*"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo ship.sh ended with an error - read the lines above.
) else (
  echo ship.sh finished.
)
pause
endlocal
exit /b %RC%
