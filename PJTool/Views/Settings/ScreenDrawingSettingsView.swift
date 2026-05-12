//
//  ScreenDrawingSettingsView.swift
//  PJTool
//
//  Created by PJ Lee + Ai on 2026/5/6.
//

import SwiftUI

struct ScreenDrawingSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(L10n.tr("legacy.key_66"), subtitle: L10n.tr("legacy.key_177"))

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

                    Button(L10n.tr("legacy.c_2")) {
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
                Text(L10n.tr("legacy.key_116"))
                    .font(.headline)
                Group {
                    Text(L10n.tr("legacy.key_225"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.tr("legacy.k_1_5_1_2_3_4_5"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Group {
                    Text(L10n.tr("legacy.key_81"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.tr("legacy.k_1_6"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Group {
                    Text(L10n.tr("legacy.key_178"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.tr("legacy.x"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("legacy.a"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Label(
                    appCoordinator.isDrawGlobalHotkeysEnabled
                        ? L10n.tr("legacy.pjtool_3")
                        : L10n.tr("legacy.pjtool_4"),
                    systemImage: appCoordinator.isDrawGlobalHotkeysEnabled ? "globe" : "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            card {
                Text(L10n.tr("legacy.key_188"))
                    .font(.headline)

                HStack(spacing: 12) {
                    Text(L10n.tr("legacy.key_121"))
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
                    L10n.tr("legacy.key_48"),
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
                    Button(L10n.tr("legacy.png_2")) {
                        appCoordinator.exportScreenDrawCanvasAsPNG()
                    }
                    .buttonStyle(.borderedProminent)

                    Text(L10n.tr("legacy.key_147"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            card {
                Text(L10n.tr("draw.dismiss.title"))
                    .font(.headline)
                Text(L10n.tr("draw.dismiss.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker(
                    L10n.tr("draw.dismiss.mode.label"),
                    selection: Binding(
                        get: { appCoordinator.drawDismissalAnimationMode },
                        set: { appCoordinator.drawDismissalAnimationMode = $0 }
                    )
                ) {
                    ForEach(DrawDismissalAnimationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if appCoordinator.drawDismissalAnimationMode == .fixed {
                    Picker(
                        L10n.tr("draw.dismiss.style.label"),
                        selection: Binding(
                            get: { appCoordinator.drawDismissalAnimationFixedStyle },
                            set: { appCoordinator.drawDismissalAnimationFixedStyle = $0 }
                        )
                    ) {
                        ForEach(DrawDismissalAnimationStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text(L10n.tr("draw.dismiss.hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topActionTitle: String {
        appCoordinator.isDrawOverlayVisible ? L10n.tr("legacy.key_148") : L10n.tr("legacy.key_101")
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
