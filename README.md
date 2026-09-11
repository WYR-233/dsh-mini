# DeepSeek Harness Mini(dsh-mini)

DeepSeek Harness 的**开源极简发行版**:一个安装包,双击装完,桌面点开即用。

- ✅ 单个 setup.exe,中文安装向导,无需命令行
- ✅ 自带 Node 运行时,电脑上什么都不用装
- ✅ 托盘常驻 + 自动开浏览器,崩溃自愈(看门狗 + 一键回档)
- ✅ 升级覆盖安装,对话记录/设置/插件全部保留

## 版本对照

| dsh-mini | 内置 dsh 内核 | 说明 |
| --- | --- | --- |
| v0.1.1(最新) | 0.1.5-rc.1 | **面板改用访问令牌(launch token)**,托盘已自动处理,双击即进面板;`--stop` 停服、`present` 工具、持久目标/提醒等新特性随内核到位 |
| v0.1.0 | 0.1.1-rc.2 | 旧内核,**稳定备用**:不带令牌机制,面板裸开即可 |

> 只发行最新版;v0.1.0 作为旧内核稳定版保留,不追发中间版本(0.1.2~0.1.4)。

## 快速开始

1. 到 [Releases](../../releases) 下载 `DeepSeekHarnessMini-Setup-*.exe`
2. 双击 → 一路「下一步」→ 完成(可选"立即启动")
3. 桌面或开始菜单点「DeepSeek Harness Mini」,托盘出现鲸鱼娘图标,浏览器自动打开面板
4. 首次使用:在面板里配置你的模型 API(设置 → 模型/凭据)

## 面板与访问令牌(0.1.5 起必读)

dsh 0.1.5 给 Web 面板加了**每次启动随机生成的访问令牌**:

- 服务启动时会打印 `dsh web: http://127.0.0.1:2233/?token=<随机串>`,只有这个带令牌的地址才能进面板;
- 直接裸开 `http://127.0.0.1:2233` 会 **401**(要你手输令牌),旧书签会失效;
- 浏览器访问一次令牌地址后,会种下 **30 天**的登录 cookie,同一地址之后免令牌(重启服务也还有效);
- **不用管这些**:托盘会自动从服务输出里抓取带令牌的地址并打开它;想手动发给手机/远程时,右键托盘 →「复制面板地址(含 token)」。

## 托盘菜单

右键托盘鲸鱼娘图标:

| 菜单 | 作用 |
| --- | --- |
| 打开面板 | 用**带令牌的地址**打开面板(服务没起就先起服务) |
| 复制面板地址(含 token) | 把完整面板地址+令牌放进剪贴板(手机/远程登录用) |
| 重启 | 重启后台服务 |
| 回档恢复 | 配置坏了?一键回到上次正常状态 |
| 开机自启 | 勾选后开机自动运行(默认关) |
| 查看日志 | 用记事本打开运行日志 |
| 退出 | 停止服务并退出 |

## 更新

下载新版安装包 → 双击 → 下一步,装完即新版。

- 安装前会自动停掉正在运行的旧版
- 对话记录、设置、已装插件**不会**被覆盖
- 版本号在安装向导标题可见

## 卸载

开始菜单 →「卸载 DeepSeek Harness Mini」,或 Windows 设置 → 应用里卸载。

(鲸鱼娘会哭一下,忍痛卸载即可;程序文件、注册表、快捷方式都会清干净。)

## 常见问题

**面板打不开 / 提示 401?** 托盘会自动带令牌打开;手动开过旧书签的话删掉重开,或右键托盘 →「复制面板地址(含 token)」拿最新地址。托盘图标还在的话右键「查看日志」;服务没起来托盘会自动重试并自愈回档。

**端口被占用?** 默认 2233。可以这样换端口启动:在安装目录按住 Shift 右键空白处 → 打开 PowerShell → 输入 `.\DshMini.exe 2255` 回车。

**数据存在哪?** 全部在安装目录的 `home\` 文件夹里(便携设计,整个目录拷走=搬家)。

## 开发者

```
dsh-mini/
├── src/            托盘启动器源码(C#,纯 ASCII)+ 图标
├── scripts/        组装/编译/生图脚本
│   ├── stage.ps1           从 npm 组装发布目录(本机/CI 通用,-DshVersion 定内核)
│   ├── build-tray.ps1      编译托盘 exe(源码非 ASCII 直接报错)
│   ├── make-wizard-assets.ps1  生成向导图 BMP
│   ├── make-icons.ps1      生成多尺寸 ico
│   ├── check-package.ps1   打包体检(内核版本/干净 home/bat 纯 ASCII)
│   ├── smoke-test.ps1      干净目录冒烟(装→启动→token 面板→重启→卸载)
│   ├── publish-gitee-release.ps1  把安装包同步成 Gitee 发行版
│   └── scan-sensitive.ps1  敏感信息扫描
├── template/home/  干净的 home 模板(无凭据无设置)
├── installer/      Inno Setup 脚本 + 中文语言包
├── assets/         托盘 exe、图标、向导图(提交进仓库,CI 直接用)
└── .github/        Actions 自动打包发 release
```

**本地出包:**

```
powershell scripts\stage.ps1 -NodeDir <便携node目录> -Registry https://registry.npmmirror.com -DshVersion 0.1.5-rc.1
powershell scripts\check-package.ps1 -DshVersion 0.1.5-rc.1
ISCC.exe /DMyAppVersion=0.1.1 /DDshVersion=0.1.5-rc.1 installer\dsh-mini.iss
```

换内核版本 = 改 `-DshVersion` 一个参数重跑;换包版本号 = 改 `-DMyAppVersion`(或直接推 `v*` 标签,CI 自动取标签号)。

**发布:** 推送 `v*` 标签,Actions 自动在 Windows runner 上组装+打包+发 Release(内核版本走 `workflow_dispatch` 入参,默认 0.1.5-rc.1)。

**国内镜像:** CI 出包后,把 Release 那份安装包同步到 Gitee 发行版:

```
$env:GITEE_TOKEN = '<私人令牌,projects 权限>'
powershell scripts\publish-gitee-release.ps1 -Tag v0.1.1 -BodyFile .github\release-notes\v0.1.1.md -Asset release\DeepSeekHarnessMini-Setup-v0.1.1.exe
```

**验收:** `powershell scripts\smoke-test.ps1 -Installer <安装包> -Uninstall`(干净目录安装→启动→裸开 401→带 token 进面板→重启仍可开→卸载 0 残留;默认用 2255 端口,不碰在跑的 DSH)。

## 许可

本项目 MIT License(见 [LICENSE](LICENSE))。内置组件许可见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。
