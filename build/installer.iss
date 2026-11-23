; Установщик информационной панели (Inno Setup 6). Собирается в GitHub Actions из Flutter-сборки.
; Версию передают через /DAppVersion=..., папку сборки — через /DSrcDir=...
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#ifndef SrcDir
  #define SrcDir "..\app\build\windows\x64\runner\Release"
#endif

[Setup]
; тот же AppId, что у Python-версии: новая версия ставится поверх старой
AppId={{6F2B7C1E-4D8A-4B5F-9C3E-2A7D1E5B8F40}
AppName=Информационная панель
AppVersion={#AppVersion}
AppPublisher=DesktopPanel
DefaultDirName={localappdata}\Programs\DesktopPanel
DefaultGroupName=Информационная панель
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=DesktopPanelSetup-{#AppVersion}
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\DesktopPanel.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; установка поверх работающей панели: установщик сам закрывает её и после установки запускает снова
CloseApplications=force
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Ярлык на рабочем столе"; GroupDescription: "Дополнительно:"
Name: "autostart"; Description: "Запускать вместе с Windows"; GroupDescription: "Дополнительно:"

[InstallDelete]
; файлы Python-версии больше не нужны
Type: filesandordirs; Name: "{app}\_internal"

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Информационная панель"; Filename: "{app}\DesktopPanel.exe"
Name: "{group}\Удалить панель"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Информационная панель"; Filename: "{app}\DesktopPanel.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "DesktopPanel"; ValueData: """{app}\DesktopPanel.exe"""; Tasks: autostart; Flags: uninsdeletevalue
; без галочки автозапуска убираем и прежний автозапуск Python-версии, чтобы не запускались обе
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "DesktopPanel"; Flags: deletevalue; Tasks: not autostart

[Run]
Filename: "{app}\DesktopPanel.exe"; Description: "Запустить панель"; Flags: nowait postinstall skipifsilent

; Данные (%APPDATA%\DesktopPanel) не удаляются ни при обновлении, ни при удалении программы.

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  // запасной путь, если панель не закрылась через диспетчер перезапуска Windows;
  // данные сохраняются через секунду после каждого изменения, так что ничего не теряется
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM DesktopPanel.exe /F', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := '';
end;
