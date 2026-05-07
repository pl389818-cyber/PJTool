//
//  ScreenDrawingSettingsView.swift
//  PJTool
//
//  Created by Codex on 2026/5/6.
//

import SwiftUI

struct ScreenDrawingSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("屏幕画图", subtitle: "独立透明画布，极简四工具 + 快捷键驱动")

            card {
                HStack(spacing: 12) {
                    Button(topActionTitle) {
                        if appCoordinator.isDrawOverlayVisible {
                            appCoordinator.hideScreenDrawOverlay()
                        } else {
                            appCoordinator.showScreenDrawOverlay()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("清空画布 (⌘⌥C)") {
                        appCoordinator.clearScreenDrawCanvas()
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 8)

                    Label(
                        appCoordinator.drawStatusMessage,
                        systemImage: appCoordinator.isDrawOverlayVisible ? "pencil.and.scribble" : "pencil.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
            }

            card {
                Text("快捷键")
                    .font(.headline)
                Group {
                    Text("颜色快捷选中")
                        .font(.subheadline.weight(.semibold))
                    Text("⌃⌥ + 1~5：快速切换 1 红 / 2 黄 / 3 绿 / 4 蓝 / 5 黑")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Group {
                    Text("工具快捷选中")
                        .font(.subheadline.weight(.semibold))
                    Text("⌘⌥ + 1~6：线 / 箭头 / 方框 / 圆形 / 错 / 对")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Group {
                    Text("画布与显示控制")
                        .font(.subheadline.weight(.semibold))
                    Text("⌘⌥ + C：清空当前画布")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("⌘⌥ + H：收起屏幕画图")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("⌘⌥ + S：展示屏幕画图")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("⌘⌥ + D：关闭画布交互（鼠标穿透）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("⌘⌥ + A：开启画布交互（可继续绘制）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Label(
                    appCoordinator.isDrawGlobalHotkeysEnabled
                        ? "当前全局快捷键已启用，可在 PJTool 后台直接触发。"
                        : "当前降级为前台快捷键，请先激活 PJTool 再触发。",
                    systemImage: appCoordinator.isDrawGlobalHotkeysEnabled ? "globe" : "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            card {
                Text("工具能力")
                    .font(.headline)
                Text("颜色：1 红 / 2 黄 / 3 绿 / 4 蓝 / 5 黑")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("图形：画线 / 箭头线 / 方框 / 圆形 / 错 / 对")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("说明：已移除文本、撤销重做、按住 Option 才能绘制等旧能力。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            card {
                Text("笔迹调校")
                    .font(.headline)

                HStack(spacing: 12) {
                    Text("手绘强度")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(appCoordinator.drawHandDrawnIntensity) },
                            set: { appCoordinator.setDrawHandDrawnIntensity(CGFloat($0)) }
                        ),
                        in: 0 ... 1
                    )
                    Text("\(Int(appCoordinator.drawHandDrawnIntensity * 100))%")
                        .font(.footnote.monospacedDigit())
                        .frame(width: 46, alignment: .trailing)
                }

                Picker(
                    "对/错风格",
                    selection: Binding(
                        get: { appCoordinator.drawMarkStyle },
                        set: { appCoordinator.setDrawMarkStyle($0) }
                    )
                ) {
                    ForEach(ScreenDrawMarkStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Button("导出画布 PNG（透明）") {
                        appCoordinator.exportScreenDrawCanvasAsPNG()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("支持透明背景导出")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topActionTitle: String {
        appCoordinator.isDrawOverlayVisible ? "收起屏幕画图" : "弹出屏幕画图"
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}
