# Windows-MoviePilot-V2

把 [MoviePilot](https://github.com/jxxghp/MoviePilot) 打包成 Windows 安装程序。内置便携 Python 3.12 与 nginx，装完双击即用，不需要 Docker、不需要配置运行环境。

每个版本严格对应上游的一个正式 Release，打包流程全部在本仓库，不依赖任何私有仓库。

## 与官方 Docker 版的区别

- 基于 Inno Setup 打包，内置便携 Python 3.12 与 nginx，免环境配置
- 启动无需解压数据，启动和停机都更快
- 认证和站点文件随安装包分发，升级安装即同步更新
- 停机只结束安装目录下的 nginx 和 python，不会动用户自己装的同名程序
- 不申请管理员权限，因此能正常看到当前用户挂载的 SMB / WebDAV 盘符

## 版本命名规则

形如 `2.15.5.d0a586a`：

- `2.15.5` 是上游 MoviePilot 发布的 Release 版本号
- `d0a586a` 是该 Release 对应的 commit hash
- 每 4 小时检查一次[上游 Releases](https://github.com/jxxghp/MoviePilot/releases)，出现新的正式 Release 才打包发版
- prerelease 和 draft 不打包
- 不跟随 `v2` 分支的滚动提交，不会打进上游未发版的代码

## 安装与运行

内置 Python 3.12，因此**系统必须是 64 位，且不支持 Win7 及更早的系统**。

1. 确认系统已安装 [Visual C++ Redistributable](https://aka.ms/vs/17/release/VC_redist.x64.exe)
2. 运行安装包。默认装到 `%LOCALAPPDATA%\Programs\MoviePilot-V2`，可在向导中改到任意非系统盘目录
3. 双击桌面 `MoviePilot-V2` 快捷方式启动，托盘出现图标即表示已启动
4. 浏览器访问 <http://127.0.0.1:3333>

默认用户名 `admin`，首次启动会随机生成密码并写入日志：`<安装目录>\config\logs\moviepilot.log`。

默认只监听本机。需要局域网访问时，编辑 `<安装目录>\config\app.env`，把 `HOST` 改为 `0.0.0.0` 后重启。

## 升级

直接运行新版本安装包，选择同一目录覆盖安装即可。

安装器会先停掉正在运行的实例，再整体替换 `MoviePilot\`、`Python\`、`Nginx\` 三个目录。用户数据全部在 `<安装目录>\config\`，升级不会触碰，无需手动备份。

## 卸载

从「设置 - 应用」或安装目录下的 `unins000.exe` 卸载。

卸载会清理程序文件，但**保留 `config\` 目录**。确认不再需要历史数据时，手动删除该目录即可。

## 常见问题

### 双击快捷方式完全没反应

看 `<安装目录>\config\launcher.log`，启动器从第一行起就往这里记录，包括起 nginx、起后端、退出码。

日志文件根本不存在，说明 `MoviePilot.vbs` 没能拉起 `launcher.cmd`（脚本宿主被安全软件拦截、`.vbs` 关联被改等）。直接双击安装目录下的 `launcher.cmd` 看窗口里的报错。

### 托盘图标自动退出

说明后端启动失败。手动运行看错误：

打开 `<安装目录>\MoviePilot` 目录，在地址栏输入 `cmd` 回车，然后执行：

```
..\Python\python.exe .\app\main.py
```

### 登录页面提示 502

502 表示 nginx 起来了但后端没起来。

- 托盘图标还在（把鼠标移到托盘区，Windows 会刷新图标列表）：后端仍在启动中，等待即可
- 没有托盘图标：后端启动失败，按上一条手动运行查看错误
- 也可查看 `<安装目录>\Nginx\logs\error.log`

### 看不到网络挂载的盘符

本安装包不申请管理员权限，正常情况下能看到当前用户挂载的所有盘符。

如果你手动以管理员身份运行了程序，就会看不到普通用户挂载的盘符——这是 Windows 的机制，需要改注册表才能打通。直接以普通权限启动即可避免。

### 停止与重启

- **托盘 - 退出**：向后端发送停机信号，等正在处理的任务结束后退出，随后自动收掉 nginx。属于优雅停机，偶尔会有较长的等待
- **重新启动**：退出后重新双击快捷方式
- **WEB 界面里的重启**：当前版本不支持，请用托盘退出后重新启动

---

## 打包说明

本仓库自带完整的封装层，fork 后即可自行打包，不依赖任何私有仓库。

### 目录结构

```
packaging/
├── build.iss                 Inno Setup 安装器脚本
├── apply-windows-patch.ps1   对上游源码的两处最小改动
├── nginx/
│   ├── nginx.conf            监听 3333
│   └── common.conf           静态资源 + 反代 3111，改编自上游 docker/nginx.common.conf
├── launcher/
│   ├── MoviePilot.vbs        入口，隐藏窗口启动 launcher.cmd
│   └── launcher.cmd          起 nginx → 起后端 → 后端退出后收掉 nginx
└── config/app.env            默认配置，仅首次安装写入
```

### 安装后的目录布局

```
<安装目录>\
├── MoviePilot.vbs      桌面快捷方式指向这里
├── launcher.cmd
├── config\             用户数据，升级和卸载都不会动
├── Python\             便携 Python 3.12
├── MoviePilot\         后端源码，升级时整体替换
└── Nginx\
    ├── conf\
    └── html\MoviePilot-Frontend\
```

### 对上游源码的改动

只有 `app/main.py` 两处，由 `packaging/apply-windows-patch.ps1` 施加：

1. 把源码根目录加入 `sys.path` —— 便携版以 `python app/main.py` 启动，否则首个 `app` 包导入就失败
2. 去掉 `start_tray()` 里的 `is_frozen()` 判断 —— 托盘图标是上游自带功能，但只对 PyInstaller 冻结版开放

端口、时区等差异全部走 `config/app.env`，不改代码。补丁脚本会校验锚点，上游重构导致锚点消失时 CI 立即失败，不会静默产出坏包。

### 工作流

| 工作流 | 触发 | 作用 |
|---|---|---|
| `build_v2.yml` | 每 4 小时 / 手动 | 发现上游新 release → 构建 → 冒烟测试 → 发版 |
| `test_package.yml` | 手动 / 改动 `packaging/` 的 PR | 构建 + 冒烟测试，不发版，安装器传成 artifact |

两者共用 `.github/actions/build-package` 和 `.github/actions/smoke-test`，构建流程只有一份。

### 冒烟测试覆盖范围

CI 会静默安装、启动、探活、静默卸载：

- 安装器编译产出、静默安装退出码
- 安装后目录布局（Python、后端、nginx、前端、认证组件、配置）
- 两处 Windows 补丁确已生效
- 后端 `http://127.0.0.1:3111/api/v1/openapi.json` 返回 200
- 前端 `http://127.0.0.1:3333/` 返回 200
- nginx 反代 `http://127.0.0.1:3333/api/v1/openapi.json` 返回 200
- 静默卸载后程序文件清理干净，且 `config\` 保留

CI 覆盖不到、需下载 artifact 到真机验证的部分：托盘图标交互、快捷方式、UAC 行为、网络挂载盘符可见性、长时间运行稳定性。
