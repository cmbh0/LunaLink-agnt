# LunaLink Agent

## 友链

- [LINUX DO](https://linux.do)

LunaLink Agent 是一款面向 Android 的 Flutter 移动端 Code Agent 应用。它将服务器连接、远程/本地文件管理、GitHub API、上下文记忆和 AI 自动化编程工作流整合到手机端，让用户可以直接在 Android 设备上完成从需求规划、工具调用、代码修改到云端构建验证的完整开发闭环。

## 核心定位

LunaLink Agent 不是普通聊天应用，而是一个移动端 AI 开发工作台：

- 通过 SSH/SFTP/FTP 连接服务器或虚拟主机。
- 通过本地工作区管理每个对话独立绑定的项目文件。
- 通过 GitHub REST API 操作仓库、文件、Issues、Actions 等资源。
- 通过 Code Agent 工作流自动规划任务、调用工具、接收结果并继续执行，直到任务完成。

## 已实现能力

### AI Agent 工作流

- 支持普通聊天、MTC 模式和 Code Agent 模式。
- Code Agent 支持 todo 规划、工具调用、结果回传、自动继续、完成后停止。
- 支持最大轮数保护和 AI 请求失败自动重试，避免任务中途因临时错误直接断开。
- 支持工具调用权限策略：默认每次询问，用户也可切换为自动批准。
- 支持工具调用模糊识别，可解析标准工具块、JSON 代码块、裸 JSON 以及常见字段别名。
- 支持中英双语工具错误提示，并附带正确调用示例，便于模型自我修正。

### 上下文、记忆与消息一致性

- 基于 `.txt` 文件持久化对话、记忆、工具结果和文件变更记录。
- 每轮 AI 请求携带近期上下文、工具结果和变更摘要。
- 支持编辑并重发、回滚、删除消息，并同步重写记忆，避免旧分支污染当前上下文。
- 记忆写入前自动备份；删除记忆时同步清理对应记忆文件和备份文件。

### 服务器与 Cloud 文件管理

- 支持 Linux 服务器模式：SSH + SFTP + 终端命令。
- 支持 SFTP 文件模式：只进行文件管理，禁用终端。
- 支持 FTP 虚拟主机模式：接入 FTP 协议客户端，支持目录列表、读写、上传、下载、删除、重命名和新建目录。
- 支持服务器重复添加识别、更新合并、删除服务器、启动时自动连接配置。
- 文件管理器顶部显示 Cloud 标识，避免和本地工作区混淆。
- 支持远程文件预览和编辑，包括文本、图片、音频、视频等常见类型。

### 本地工作区

- 每个对话可绑定独立本地工作区。
- 支持创建、选择、绑定、解绑工作区。
- 工作区自动创建 `.backup` 目录，用于本地文件覆盖前备份。
- AI 可通过工具列目录、读文件、写文件和创建目录。
- 路径安全检查禁止访问绝对路径、`..` 和 `.backup`，降低误操作风险。
- 本地工作区页面显示本地标识，和 Cloud 文件管理明确区分。

### GitHub 与云端构建

- 支持 GitHub Token 连接检查。
- 支持通用 `github_api` 工具，可调用 GitHub REST API 支持的 GET/POST/PATCH/PUT/DELETE 接口。
- 支持仓库文件读取、创建、更新、删除以及 Actions 构建触发和日志拉取。
- 适合配合 GitHub Actions 完成移动端云编译和 Release 构建验证。

### UI 与交互

- Android Flutter 工程，使用 Material 3。
- 默认月亮主题、分层背景、低成本粒子绘制。
- Code Agent 编写代码时显示实时代码追踪悬浮窗，支持代码视图和 Diff 视图。
- 输入区域支持任务列表胶囊，点击查看当前 todo 进度。
- 思考过程渲染做了异常换行合并，避免单字/短词频繁换行导致阅读困难。
- 工具调用结果、文件变更和错误信息采用卡片化展示，便于用户审核和追踪。

## 工程结构

```text
lib/
  models/          服务器、AI Provider、消息、工具调用、文件变更、本地工作区模型
  services/        SSH/SFTP/FTP、AI Client、JSON txt 存储、状态管理与工具执行
  screens/         连接页、文件管理页、文件查看器、Agent 对话页、工作区页面
  theme/           月亮主题与视觉规范
  widgets/         月亮背景和通用脚手架
.github/
  workflows/       Flutter Android 云端构建流程
```

## 运行

```bash
flutter pub get
flutter run
```

## 构建

项目支持通过 GitHub Actions 进行 Android APK 云端构建。常规本地构建命令：

```bash
flutter analyze
flutter build apk --release
```

## 项目状态

LunaLink Agent 仍在持续开发中，当前重点方向包括：

- 提升 FTP/SFTP/SSH 文件操作兼容性。
- 完善 Code Agent 自动化任务执行稳定性。
- 在真实 Android 设备上持续验证 UI、权限、文件管理和云编译流程。