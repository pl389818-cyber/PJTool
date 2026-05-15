# 音频提取术语与标题文案规范（MD）

更新时间：2026-05-15

## 1. 适用范围
1. 适用于 `音频提取（MP3）` 模块相关文案。
2. 本文档当前仅定义术语与标题文案规范，不扩展 `mp3->md` 功能实现。

## 2. 统一文案规范
1. 音频提取副标题固定写法：`Video mp3 md`。
2. 禁止写法：旧的连字符版本副标题。
3. 本地化 key 固定：`section.audioExtract.subtitle`。
4. 中文与英文 value 当前保持一致：`Video mp3 md`。

## 3. 同步要求
1. 修改副标题时必须同步：
   - `PJTool/Lang/zh-Hans.lproj/Localizable.strings`
   - `PJTool/Lang/en.lproj/Localizable.strings`
2. 禁止在 View 内硬编码副标题，统一通过 `L10n.tr("section.audioExtract.subtitle")` 渲染。

## 4. 验收要求
1. 切换中文后副标题显示 `Video mp3 md`。
2. 切换英文后副标题显示 `Video mp3 md`。
3. 全局搜索不应出现旧的连字符版本副标题（历史记录除外）。
