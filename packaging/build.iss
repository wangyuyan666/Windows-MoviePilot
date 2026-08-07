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

; 全程不提权，两个原因：
;   1. 提权后看不到普通用户挂载的网络盘符（SMB/WebDAV）。
;   2. 运行期的 config\user.db、Nginx\logs 等都写在安装目录里，而启动器是普通
;      用户身份运行的。装进 C:\Program Files 会在启动后才炸（SQLite 报
;      unable to open database file），所以不提供全局安装选项。
; 因此这里没有 PrivilegesRequiredOverridesAllowed，{autopf} 恒等于
; %LOCALAPPDATA%\Programs，当前用户可写。
PrivilegesRequired=lowest

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

[CustomMessages]
chinesesimplified.DirNotWritable=当前用户无法写入所选目录：%n%n%1%n%nMoviePilot 以普通用户权限运行，配置和数据库都保存在安装目录中，请改选一个可写的位置（如默认目录）。
english.DirNotWritable=The current user cannot write to the selected folder:%n%n%1%n%nMoviePilot runs without elevation and keeps its configuration and database inside the install folder. Choose a writable location (for example the default one).

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

{
  安装目录必须对当前用户可写：user.db / launcher.log / Nginx\logs 都写在安装
  目录里，而启动器不提权。用户仍可在向导里手打 C:\Program Files\... 之类的只读
  路径，那种情况下要到首次启动才报错。这里用一次真实写入探测，在选目录那一步
  就拦掉。

  注意：本注释块内不能出现右花括号，Pascal 注释会被它提前闭合。
}
function DirIsWritable(Dir: String): Boolean;
var
  Probe: String;
  Created: Boolean;
begin
  Created := not DirExists(Dir);
  if Created then begin
    if not ForceDirectories(Dir) then begin
      Result := False;
      Exit;
    end;
  end;

  Probe := AddBackslash(Dir) + 'mp_write_test.tmp';
  Result := SaveStringToFile(Probe, 'x', False);
  if Result then
    DeleteFile(Probe);

  { 探测过程中新建的目录不留下来；ForceDirectories 若建了多级，这里只删末级，
    但那种情况下目录本来就可写，安装马上会重新建出来。 }
  if Created then
    RemoveDir(Dir);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    if not DirIsWritable(WizardDirValue) then begin
      MsgBox(FmtMessage(CustomMessage('DirNotWritable'), [WizardDirValue]), mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  StopRunningInstance();
  Result := True;
end;
