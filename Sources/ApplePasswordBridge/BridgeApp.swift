import SwiftUI

@main
struct BridgeApp: App {
    @StateObject private var model = BridgeModel()

    var body: some Scene {
        MenuBarExtra("密码桥", systemImage: "key.horizontal.fill") {
            BridgeMenu(model: model)
        }
        .menuBarExtraStyle(.window)
    }

}

private struct BridgeMenu: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("密码桥")
                        .font(.headline)
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            Toggle("监听 Apple 密码授权窗口", isOn: $model.monitoringEnabled)
            Toggle("识别后自动填入", isOn: $model.automaticFillEnabled)
            Toggle("辅助功能失败时使用本地 OCR", isOn: $model.ocrFallbackEnabled)

            VStack(alignment: .leading, spacing: 8) {
                Text("填入速度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("填入速度", selection: $model.fillSpeed) {
                    ForEach(FillSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Button {
                Task { await model.fillNow() }
            } label: {
                Label("立即填入", systemImage: "arrow.right.to.line.compact")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("命中模式：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("应用规则", selection: $model.applicationRuleMode) {
                        ForEach(ApplicationRuleMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Button(action: model.chooseApplication) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(model.applicationRuleMode == .allowlist ? "添加允许的应用" : "添加排除的应用")
                }

                if model.activeApplicationRules.isEmpty {
                    Text(model.applicationRuleMode == .allowlist ? "没有允许的应用" : "没有排除的应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.activeApplicationRules) { application in
                                HStack(spacing: 8) {
                                    Image(systemName: "app")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(application.displayName)
                                        Text(application.bundleIdentifier)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button {
                                        model.removeApplication(application)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("移除")
                                }
                            }
                        }
                    }
                    .frame(
                        height: min(CGFloat(model.activeApplicationRules.count) * 38, 140)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PermissionRow(
                    title: "辅助功能",
                    granted: model.accessibilityGranted,
                    request: model.requestAccessibility,
                    openSettings: model.openAccessibilitySettings
                )
                PermissionRow(
                    title: "屏幕录制",
                    granted: model.screenRecordingGranted,
                    request: model.requestScreenRecording,
                    openSettings: model.openScreenRecordingSettings
                )
            }

            Divider()

            Toggle("登录后自动启动", isOn: Binding(
                get: { model.launchAtLogin },
                set: model.setLaunchAtLogin
            ))

            HStack {
                Label("⌃⌥⌘P", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear(perform: model.refreshPermissionStatus)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            if granted {
                Text("已允许")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("授权", action: request)
                    .controlSize(.small)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("打开系统设置")
            }
        }
    }
}
