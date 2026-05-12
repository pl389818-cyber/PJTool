# 音频提取（MP3）复刻说明

## 1. 目标
- 输入来源：
- 本地文件（`mp4/mov/mkv/webm/mp3`）
- 在线视频链接（主支持 B站/YouTube，其他站点 `best effort`）
- 输出：
- 单个 `mp3` 文件
- 输出目录格式：`outputs/YYYYMMDD_HHMMSS_<source_tag>/`

## 2. 当前实现结构
- CLI 脚本：
- `/Users/jamie/CodexAi/macDemo/tools/audio_extract_cli.py`
- macOS GUI：
- `/Users/jamie/CodexAi/macDemo/macDemo/macDemo/ContentView.swift`
- 工程配置：
- `/Users/jamie/CodexAi/macDemo/macDemo/macDemo.xcodeproj/project.pbxproj`
- 协作规范：
- `/Users/jamie/CodexAi/macDemo/AGENTS.md`

## 3. CLI 设计（核心可复用）
### 3.1 参数
- `source`：本地文件路径或 URL
- `--output-dir`：输出目录（默认 `outputs`）
- `--install-deps`：自动安装缺失依赖
- `--audio-quality`：`0-9` 或 `best/high/medium/low`（默认 `0`）

### 3.2 主流程
1. 判断 `source` 是否 URL。
2. 检查依赖：
- 本地模式：`ffmpeg`、`ffprobe`
- URL 模式：`ffmpeg`、`ffprobe`、`yt-dlp`
3. 构建输出目录：
- URL 优先提取视频 ID（BV号 / YouTube 11位ID）
- 本地用文件名清洗后的标签
4. 执行提取：
- 本地：`ffmpeg -vn -codec:a libmp3lame -q:a <quality>`
- URL：`yt-dlp -x --audio-format mp3 --audio-quality <quality>`
5. 校验结果：
- 文件存在且大小 > 0
- `ffprobe` 可读取时长，且时长 > 0
6. 输出日志和退出码：
- `0` 成功
- `2` 可预期失败
- `130` 用户中断

### 3.3 错误分流
- 网络 DNS 失败
- 429 限流
- 视频不可用（下架/区域限制）
- URL 不支持
- 本地文件不存在/格式不支持/无音轨
- 所有错误统一格式：
- `原因: ...`
- `下一步命令: ...`

## 4. GUI 设计（SwiftUI）
### 4.1 界面能力
- 来源切换（本地文件 / 在线链接）
- 本地文件选择（`NSOpenPanel`）
- 输出目录选择
- 音质选择（best/high/medium/low）
- 自动安装依赖开关
- 按钮：
- 开始提取
- 停止
- 打开输出目录
- 定位最新 MP3
- 日志面板（实时展示 CLI 输出）

### 4.2 调用方式
- GUI 使用 `Process` 调起 Python + CLI。
- 会在日志中打印实际运行解释器路径：
- `[运行] python=...`

## 5. 关键踩坑与修复
### 5.1 `xcrun: cannot be used within an App Sandbox`
- 现象：
- GUI 内执行时触发 `xcrun` 相关错误。
- 原因：
- App Sandbox + Xcode Python/工具链路径在子进程调用时受限。
- 处理：
- 在工程中关闭 App Sandbox（Debug/Release）：
- `ENABLE_APP_SANDBOX = NO`
- 让 GUI 尽量优先使用 Homebrew Python。

### 5.2 `Operation not permitted` 读取脚本
- 现象：
- `python3: can't open file ... audio_extract_cli.py`
- 原因：
- 沙箱限制读工作区脚本。
- 处理：
- 同上，关闭 App Sandbox 后恢复。

## 6. 从零复刻步骤
### 6.1 环境准备
```bash
brew install ffmpeg yt-dlp python
```

### 6.2 CLI 直接运行验证
```bash
python3 /Users/jamie/CodexAi/macDemo/tools/audio_extract_cli.py "/path/to/video.mp4"
python3 /Users/jamie/CodexAi/macDemo/tools/audio_extract_cli.py "https://www.bilibili.com/video/BVxxxxxxxxxxx"
python3 /Users/jamie/CodexAi/macDemo/tools/audio_extract_cli.py "<source>" --install-deps --audio-quality best
```

### 6.3 GUI 编译
```bash
xcodebuild \
  -project /Users/jamie/CodexAi/macDemo/macDemo/macDemo.xcodeproj \
  -scheme macDemo \
  -destination platform=macOS \
  -derivedDataPath /Users/jamie/CodexAi/macDemo/.derivedData \
  clean build
```

### 6.4 GUI 启动
- App 产物：
- `/Users/jamie/CodexAi/macDemo/.derivedData/Build/Products/Debug/macDemo.app`
- 启动后在日志确认：
- 出现 `[运行] python=...`
- 如果失败，优先贴这行和后续错误段排查。

## 7. 验收清单
- 本地文件提取成功，生成 mp3。
- B站链接提取成功，生成 mp3。
- YouTube 链接提取成功（网络可达情况下）。
- 输出目录符合 `outputs/YYYYMMDD_HHMMSS_<source_tag>/`。
- 失败时有明确“原因 + 下一步命令”。
