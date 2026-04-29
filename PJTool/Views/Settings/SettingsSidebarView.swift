//
//  SettingsSidebarView.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            navList
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    Text("设置")
                        .font(.headline)
                    Text("PJTool Studio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "sidebar.leading" : "sidebar.left")
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "展开侧栏" : "折叠侧栏")
        }
    }

    private var navList: some View {
        VStack(spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                sidebarRow(section: section)
            }
        }
    }

    private func sidebarRow(section: SettingsSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbolName)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .primary)

                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}
