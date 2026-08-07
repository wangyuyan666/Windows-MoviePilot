; MoviePilot Windows 便携版安装器
;
; 由 .github/workflows/build_v2.yml 编译，版本号通过 /DMyAppVersion 传入：
;   iscc /DMyAppVersion=2.15.5.abc1234 packaging\build.iss
;
; 编译前工作区需已准备好（相对本文件的上一级目录）：
;   ..\MoviePilot\   上游 release 源码 + 插件 + 认证组件 + 已应用 Windows 补丁
;   ..\Python\       便携 Python 运行时
;   ..\Nginx\        nginx + conf + html\MoviePilot-Frontend

#define MyAppName "MoviePilot-V2"
#define MyAppPublisher "Windows-MoviePilot"
#define MyAppURL "https://github.com/jxxghp/MoviePilot"
#define MyAppEntry "MoviePilot.vbs"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0.dev"
#endif

[Setup]
; AppId 决定升级识别与卸载项，一经发布不可更改
AppId={{6F2C1A47-9E3D-4B8A-A5C6-2D71E0B4F893}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
VersionInfoVersion=0.0.0.0
VersionInfoTextVersion={#MyAppVersion}

; 不申请管理员权限：提权后看不到普通用户挂载的网络盘符（SMB/WebDAV）。
; 用户仍可在安装向导中手动切换为全局安装。
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

OutputDir=..\exe\build
OutputBaseFilename=MoviePilot-V2-{#MyAppVersion}
SetupIconFile=..\MoviePilot\app.ico
UninstallDisplayIcon={app}\MoviePilot\app.ico
UninstallDisplayName={#MyAppName} {#MyAppVersion}

Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; 后端源码。排除 .git 与开发期目录，减小体积
Source: "..\MoviePilot\*"; DestDir: "{app}\MoviePilot"; \
    Excludes: ".git,.github,tests,docs,skills,*.pyc,__pycache__"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; 便携 Python 运行时
Source: "..\Python\*"; DestDir: "{app}\Python"; \
    Excludes: "*.pyc,__pycache__"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; nginx + 前端静态资源
Source: "..\Nginx\*"; DestDir: "{app}\Nginx"; \
    Excludes: "logs,temp"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; 启动器
Source: "launcher\{#MyAppEntry}"; DestDir: "{app}"; Flags: ignoreversion
Source: "launcher\launcher.cmd"; DestDir: "{app}"; Flags: ignoreversion

; 默认配置：仅首次安装写入，升级和卸载都不动它
Source: "config\app.env"; DestDir: "{app}\config"; Flags: onlyifdoesntexist uninsneveruninstall

[Dirs]
Name: "{app}\config"; Flags: uninsneveruninstall
Name: "{app}\Nginx\logs"
Name: "{app}\Nginx\temp"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppEntry}"; IconFilename: "{app}\MoviePilot\app.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppEntry}"; IconFilename: "{app}\MoviePilot\app.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppEntry}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: shellexec postinstall skipifsilent nowait

[UninstallDelete]
; nginx 运行期产生的文件不在安装清单里，需显式清理
Type: filesandordirs; Name: "{app}\Nginx\logs"
Type: filesandordirs; Name: "{app}\Nginx\temp"

[Code]
{
  安装和卸载前停掉正在运行的实例，否则文件被占用会导致覆盖失败。

  只结束安装目录下的进程：用户自行安装的 nginx / python 不受影响，
  这是本项目相对直接 taskkill 全部同名进程的关键区别。
}
procedure StopRunningInstance();
var
  ResultCode: Integer;
  Script: String;
begin
  Script :=
    '$target = ''' + ExpandConstant('{app}') + '''; ' +
    '$procs = Get-Process -Name nginx,python,pythonw -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -and $_.Path.StartsWith($target, [System.StringComparison]::OrdinalIgnoreCase) }; ' +
    'if ($procs) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }';

  Exec(ExpandConstant('{cmd}'), '/c powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + Script + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningInstance();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopRunningInstance();
  Result := True;
end;
