# DeepSeek Harness Mini(dsh-mini)

DeepSeek Harness 的**开源极简发行版**:一个安装包,双击装完,桌面点开即用。

- ✅ 单个 setup.exe,中文安装向导,无需命令行
- ✅ 自带 Node 运行时,电脑上什么都不用装
- ✅ 托盘常驻 + 自动开浏览器,崩溃自愈(看门狗 + 一键回档)
- ✅ 升级覆盖安装,对话记录/设置/插件全部保留

## 快速开始

1. 到 [Releases](../../releases) 下载 `DeepSeekHarnessMini-Setup-*.exe`
2. 双击 → 一路「下一步」→ 完成(可选"立即启动")
3. 桌面或开始菜单点「DeepSeek Harness Mini」,托盘出现鲸鱼娘图标,浏览器自动打开面板
4. 首次使用:在面板里配置你的模型 API(设置 → 模型/凭据)

## 托盘菜单

右键托盘鲸鱼娘图标:

| 菜单 | 作用 |
| --- | --- |
| 打开面板 | 在浏览器打开 `http://127.0.0.1:2233` |
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

**面板打不开?** 托盘图标还在的话右键「查看日志」;服务没起来托盘会自动重试并自愈回档。

**端口被占用?** 默认 2233。可以这样换端口启动:在安装目录按住 Shift 右键空白处 → 打开 PowerShell → 输入 `.\DshMini.exe 2255` 回车。

**数据存在哪?** 全部在安装目录的 `home\` 文件夹里(便携设计,整个目录拷走=搬家)。

## 开发者

```
dsh-mini/
├── src/            托盘启动器源码(C#,纯 ASCII)+ 图标
├── scripts/        组装/编译/生图脚本
│   ├── stage.ps1           从 npm 组装发布目录(本机/CI 通用)
│   ├── build-tray.ps1      编译托盘 exe
│   ├── make-wizard-assets.ps1  生成向导图 BMP
│   ├── make-icons.ps1      生成多尺寸 ico
│   └── scan-sensitive.ps1  敏感信息扫描
├── template/home/  干净的 home 模板(无凭据无设置)
├── installer/      Inno Setup 脚本 + 中文语言包
├── assets/         托盘 exe、图标、向导图(提交进仓库,CI 直接用)
└── .github/        Actions 自动打包发 release
```

**本地出包:**

```
powershell scripts\stage.ps1 -NodeDir <便携node目录> -Registry https://registry.npmmirror.com
ISCC.exe installer\dsh-mini.iss
```

**发布:** 推送 `v*` 标签,Actions 自动在 Windows runner 上组装+打包+发 Release。

## 许可

本项目 MIT License(见 [LICENSE](LICENSE))。内置组件许可见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。
