@echo off
rem Geraetepruefung: Trainer und Zwift-Controller einmal am echten Geraet erfassen (nur lesen).
rem Doppelklick oder Kommandozeile; Optionen siehe: geraete-pruefen.cmd --help
setlocal
chcp 65001 >nul
for %%I in ("%~dp0..") do set "REPO=%%~fI"
set "PY=%REPO%\bridge\.venv\Scripts\python.exe"
if not exist "%PY%" goto novenv
"%PY%" "%~dp0ble_discovery.py" %*
set "RC=%ERRORLEVEL%"
goto ende

:novenv
echo Das Python-Umfeld der Bridge fehlt: %PY%
echo.
echo Einmalig einrichten ^(Python 3.12 muss installiert sein^):
echo   cd "%REPO%\bridge"
echo   py -3.12 -m venv .venv
echo   .venv\Scripts\pip install -e ".[test]"
echo Danach diese Datei erneut starten.
set "RC=9"

:ende
rem Bei Doppelklick das Fenster offen lassen, damit die Ausgabe lesbar bleibt.
echo %cmdcmdline% | "%SystemRoot%\System32\find.exe" /i "/c" >nul && pause
exit /b %RC%
