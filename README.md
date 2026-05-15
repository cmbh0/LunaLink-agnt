# LunaLink Agent

LunaLink Agent 是一个面向 Android 的 Flutter 应用：SSH/SFTP 连接 Linux 服务器、服务器信息面板、远程文件管理、文件预览/编辑、自动配置 FTP，以及类 Trae/Codex CLI 的 AI 编程代理对话工作流。

## 已做齐的实际功能
- Android Flutter 工程、Material 3、默认月亮主题、分层背景和低成本粒子绘制。
- SSH/SFTP：密码或私钥连接、远程命令、系统信息读取、目录列表、读写、删除、重命名、创建文件/目录。
- 文件管理：类 MT 管理器交互、进入/返回、刷新、新建、上传、下载到应用目录、删除确认、重命名。
- 文件查看：文本编辑保存、图片查看、音频播放、视频播放，远程媒体会先缓存到本地临时目录。
- FTP 创建：通过 SSH 在远程 Linux 上安装并配置 vsftpd，输出账号、密码和主机信息。
- AI Provider：OpenAI 通用格式、Gemini、Claude、REST/OpenAI 兼容接口。
- Agent 对话：类 Trae/Codex 的独立页面、自动运行策略、AI 服务配置、工具授权卡片、文件变更保存/拒绝卡片。
- Tool Registry 基础：`ssh_exec`、`list_files`、`read_file`、`write_file`，所有写入/终端执行都可走授权流程。
- 记忆与回滚：基于 `.txt` 文件保存 JSON，写入前自动备份，工具执行和文件变更写入 ChangeJournal。

## 工程结构
```text
lib/
  models/          服务器、AI Provider、消息、工具调用、文件变更模型
  services/        SSH/SFTP、AI Client、JSON txt 存储、状态与 Tool 执行
  screens/         连接页、文件管理页、文件查看/播放器、Agent 对话页
  theme/           月亮主题
  widgets/         月亮背景和通用脚手架
```

## 运行
```bash
flutter pub get
flutter run
```

当前执行环境没有 Flutter SDK，无法本地编译验证；源码已按实际 Flutter Android 项目落盘。