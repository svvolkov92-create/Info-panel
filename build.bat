@echo off
chcp 65001 >nul
rem Сборка установщика на Windows: нужен Python 3.9+ и Inno Setup 6 (jrsoftware.org/isdl.php).
setlocal
cd /d "%~dp0"
if "%1"=="" (set VER=1.0.0) else (set VER=%1)

echo [1/3] PyInstaller...
python -m pip install --upgrade pyinstaller || goto :fail

echo [2/3] DesktopPanel.exe...
python -m PyInstaller --noconfirm --clean --windowed --onedir --name DesktopPanel ^
  --icon build\icon.ico --distpath dist --workpath build\tmp --specpath build\tmp ^
  desktop_panel.pyw || goto :fail

echo [3/3] Установщик...
set ISCC="%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist %ISCC% set ISCC="%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
if not exist %ISCC% (
  echo Inno Setup 6 не найден. Программа собрана в dist\DesktopPanel, установщик не сделан.
  goto :end
)
%ISCC% /DAppVersion=%VER% build\installer.iss || goto :fail
echo.
echo Готово: dist\DesktopPanelSetup-%VER%.exe
goto :end

:fail
echo.
echo Сборка не удалась, сообщение об ошибке выше.
:end
pause
