; Установщик информационной панели (Inno Setup 6).
; Собирается из build.bat или в GitHub Actions; версию передают через /DAppVersion=...
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F2B7C1E-4D8A-4B5F-9C3E-2A7D1E5B8F40}
AppName=Информационная панель
AppVersion={#AppVersion}
AppPublisher=DesktopPanel
DefaultDirName={localappdata}\Programs\DesktopPanel
DefaultGroupName=Информационная панель
DisableProgramGroupPage=yes
; ставим для текущего пользователя — права администратора не нужны
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=DesktopPanelSetup-{#AppVersion}
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\DesktopPanel.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; панель открыта — установщик предложит её закрыть
AppMutex=Local\DesktopPanelSingleInstance
CloseApplications=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Ярлык на рабочем столе"; GroupDescription: "Дополнительно:"
Name: "autostart"; Description: "Запускать вместе с Windows"; GroupDescription: "Дополнительно:"

[Files]
Source: "..\dist\DesktopPanel\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Информационная панель"; Filename: "{app}\DesktopPanel.exe"
Name: "{group}\Удалить панель"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Информационная панель"; Filename: "{app}\DesktopPanel.exe"; Tasks: desktopicon

[Registry]
; тот же ключ, что и галочка «Автозапуск» в настройках панели, — они не спорят друг с другом
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "DesktopPanel"; ValueData: """{app}\DesktopPanel.exe"""; Tasks: autostart; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "DesktopPanel"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\DesktopPanel.exe"; Description: "Запустить панель"; Flags: nowait postinstall skipifsilent

; Данные (%APPDATA%\DesktopPanel) не удаляются ни при обновлении, ни при удалении программы.
