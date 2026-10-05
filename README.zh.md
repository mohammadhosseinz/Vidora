# Vidora

[English](README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md)

<img src="assets/brand/vidora-logo.png" width="144" alt="Vidora 标志">

Vidora 是一款免费的本地视频下载应用，使用 Flutter、yt-dlp、FFmpeg 和 Deno。界面支持英语、波斯语、阿拉伯语和中文，并支持波斯语与阿拉伯语的从右到左布局。**默认语言为英语**，可在语言菜单中切换。

## 关于我们
**作者：Zolfaghari（ذوالفقاری）。** 我们希望让本地视频下载更简单，并尊重您的隐私。

**请支持我们！** 您的支持将帮助我们继续开发 Vidora、修复问题并发布更新。支持完全自愿，所有功能仍然免费。您可以通过“关于 Vidora”或爱心按钮查看支持方式。

## 功能
- 粘贴链接后自动检查，显示标题、预览图和可用画质。
- 选择画质、封装格式和保存目录，显示已知或估计的下载大小，包含单独的音频。
- 下载队列、进度、速度、取消、重试以及打开输出目录。
- 支持直连、系统代理以及自定义 HTTP/SOCKS 代理。
- 可选的站点专用 Netscape cookies.txt 文件；操作后删除临时副本。
- 视频下载以及音视频合并均在用户设备上完成。

Vidora 没有应用后端、云存储或应用账号。它会连接原始视频与缩略图网站；支持页面不会收到视频链接、Cookie 文件或下载的视频。

## 运行与构建
当前版本为 **0.1.7**。Windows x64 版本已在本地构建和测试。包含 macOS、Linux 的源码与打包脚本，但尚未在相应原生系统上验证构建。Android 尚未实现；DownloadEngine 接口为后续引擎适配提供边界。

开发需要 Flutter 和目标系统的桌面构建工具，已测试环境为 Flutter 3.41.2 / Dart 3.11。完整安装包的用户不需要手动安装 Python、FFmpeg 或 Deno。

```powershell
flutter pub get
$env:LOCAL_VIDEO_TOOLS = (Resolve-Path runtime/windows).Path
flutter run -d windows
```

```sh
flutter analyze
flutter test
```

参阅[构建与打包指南](docs/BUILD.md)。本地开发目录包含 Windows 引擎，但可执行文件不提交到 Git；首次克隆后需要准备运行引擎。本地安装包位于 dist，该目录也不提交到 Git。[贡献指南](CONTRIBUTING.md)与[安全说明](SECURITY.md)。

## 支持开发
| 币种 | 网络 | 公开收款地址 |
| --- | --- | --- |
| USDT | 仅 BSC / BEP20 | `0x9a350193884756c2ff75e58847d8eff5441c27bf` |
| TRX | TRON — 仅 TRX | `TBiSUJuPZfLAJ9VHiQuGpNVPzsEYixgp13` |

应用为每个地址提供单独的复制按钮。请勿向 TRX 地址发送 USDT，也不要使用 Ethereum/TRON 向 BSC 的 USDT 地址充值。这些地址由项目所有者提供，开发者尚未验证其所有权或实际到账。请向收款平台确认最低充值金额、地址有效期和充值状态。应用不会连接钱包、创建交易或验证付款。公开支持配置位于 assets/support.json。[支持说明](docs/SUPPORT.md)。

## 限制与隐私
站点支持采用尽力而为原则，不保证所有站点与链接均可下载。DRM、登录限制、反机器人检查、地区限制和网站变化可能导致失败；Cookie 不能保证成功。队列不会在重启后保留。更换封装格式不会转换编码；遇到兼容问题可尝试 MKV。断电或强制结束程序可能留下临时文件。Windows 安装包尚未进行 Authenticode 签名。请勿在问题报告中提交真实 Cookie 或账号秘密。

## 许可证
Vidora 自身源码采用 [MIT](LICENSE)，依赖组件保留各自的许可证。本地 FFmpeg 为 GPLv3 构建；公开分发相关二进制安装包前，需要提供完整对应源码、构建信息及所链接库的源码。当前记录尚未完成这一要求。[第三方许可证说明](THIRD_PARTY_NOTICES.md)。
