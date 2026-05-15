# spec_audio_01 - 入口与配置页骨架

## 目标
1. 左侧新增平级菜单 `音频提取`。
2. 右侧新增配置页 `AudioExtractSettingsView`。
3. 建立独立状态容器，不与四模块状态机耦合。

## 本步实现
1. `SettingsSection` 新增 `audioExtract`，补标题/副标题/图标映射。
2. `SettingsSidebarView` 主导航新增 `音频提取`。
3. `ContentView` 新增 `audioExtract` 页面分支。
4. 新增 `AudioExtractViewModel`（来源、输入、输出目录、音质、日志、运行状态）。
5. 新增 `AudioExtractSettingsView`：
   - 来源切换（本地/URL）
   - 输入区（文件选择或 URL 输入）
   - 输出目录选择
   - 音质选择
   - 自动安装依赖开关
   - 开始/停止
   - 实时日志区

## 验收
1. 左侧出现第 5 项 `音频提取`。
2. 点击后右侧出现完整配置页骨架。
3. 页面交互不影响录屏/PiP/画图/视频剪切页面行为。

## 非目标
1. 本步不要求完整提取链路成功。
2. 本步不改总 AGENTS/SPEC 的“四模块固定”主声明。
