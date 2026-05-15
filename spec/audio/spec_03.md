# spec_audio_03 - 文案收敛（Video mp3 md）

## 目标
1. 将音频提取副标题文案统一为 `Video mp3 md`。
2. 保持本地化 key 不变，仅修改 value，避免影响现有 UI 绑定。

## 本步实现
1. 更新 `section.audioExtract.subtitle`：
   - `zh-Hans`：`Video mp3 md`
   - `en`：`Video mp3 md`
2. 保持 `AudioExtractSettingsView` 的读取方式不变，继续通过 `L10n.tr("section.audioExtract.subtitle")` 渲染。

## 验收
1. 中文界面显示：`Video mp3 md`。
2. 英文界面显示：`Video mp3 md`。
3. 代码与本地化资源中不再出现旧的连字符版本写法（历史提交记录除外）。

## 回归清单
1. 音频提取其余文案与功能行为不变。
2. 录屏/PiP/屏幕画图/视频剪切行为无回归。
