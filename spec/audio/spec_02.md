# spec_audio_02 - 本地+URL 提取闭环

## 目标
1. 打通本地文件与在线 URL 的 MP3 提取。
2. 输出目录遵循 `outputs/YYYYMMDD_HHMMSS_<source_tag>/`。
3. 提供实时日志、停止、结果校验、可读错误恢复。

## 本步实现
1. 新增 `AudioExtractService`：
   - 本地模式：`ffmpeg -vn -codec:a libmp3lame -q:a <quality>`
   - URL 模式：`yt-dlp -x --audio-format mp3 --audio-quality <quality>`
2. 依赖解析：
   - `ffmpeg/ffprobe` 复用现有 `FFmpegBinaryService`
   - `yt-dlp/python` 按“项目内优先 + 系统兜底”解析
3. 结果校验：
   - 文件存在
   - 文件大小 > 0
   - `ffprobe` 时长 > 0
4. 错误分流输出：
   - `原因: ...`
   - `下一步命令: ...`
5. 停止能力：运行中可终止子进程并更新状态。
6. 补齐中英文本地化 key（菜单、按钮、状态、错误模板）。

## 验收
1. 本地 `mp4/mov/mkv/webm/mp3` 任一输入可导出 MP3。
2. 通用视频 URL 在网络可达条件下可导出 MP3。
3. 点击“停止”可中断任务并给出可读状态。
4. 日志区可实时看到命令与错误输出。
5. 失败时统一输出“原因 + 下一步命令”。

## 回归清单
1. 录屏/PiP/屏幕画图/视频剪切行为无回归。
2. 菜单栏录屏与 PiP 状态显示不受影响。
3. 中英切换后音频提取页文案同步。

## 自检命令
1. `xcodebuild -project PJTool.xcodeproj -scheme PJTool -destination 'platform=macOS' build`
2. `Scripts/run_logic_checks.sh`
