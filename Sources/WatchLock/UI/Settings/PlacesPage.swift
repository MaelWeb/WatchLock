import SwiftUI

/// 场景页：信任场所（在家 / 办公室等已知网络里自动暂停自动锁定）。
///
/// 规则、依据与安全边界见 `TrustedPlace`。界面上要如实交代两件事：
/// 1. 网关地址可被同网络里的设备伪造，这是便利特性，不是安全边界；
/// 2. Wi-Fi 名称需要定位授权，但授权是**可选**的，不授权功能照常工作。
struct PlacesPage: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    @State private var newName = ""
    @State private var saveMessage: String?
    @State private var placeToDelete: TrustedPlace.Place?

    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsDetail {
            VStack(alignment: .leading, spacing: WLSpacing.md) {
                switchCard
                currentNetworkCard
                placesCard
                WiFiNameCard(access: session.trustedPlaces.wifiAccess)
                Text("网络指纹只在本机比对，不上传。它可以被同一网络里的设备伪造，所以这是方便功能，不是安全防线；离开该网络后会立即恢复自动锁定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { session.trustedPlaces.refreshSnapshot() }
        .onReceive(refreshTimer) { _ in session.trustedPlaces.refreshSnapshot() }
        .confirmationDialog(
            "删除信任场所「\(placeToDelete?.name ?? "")」？",
            isPresented: Binding(get: { placeToDelete != nil }, set: { if !$0 { placeToDelete = nil } }),
            presenting: placeToDelete
        ) { place in
            Button("删除", role: .destructive) { session.removeTrustedPlace(id: place.id) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除后，在该网络里将恢复自动锁定。")
        }
    }

    // MARK: - 总开关

    private var switchCard: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            Toggle("在信任场所自动暂停", isOn: Binding(
                get: { settings.trustedPlaceEnabled },
                set: { newValue in
                    settings.trustedPlaceEnabled = newValue
                    session.syncTrustedPlaceNow()
                }
            ))
            .help("连接到你保存过的网络（如家里、办公室）时，不再自动锁屏")
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(statusTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
    }

    private var statusLine: String {
        if !settings.trustedPlaceEnabled { return String(localized: "已关闭") }
        if settings.trustedPlaces.isEmpty { return String(localized: "还没有信任场所，保存后才会生效。") }
        if let name = settings.activeTrustedPlaceName {
            return settings.trustedPlaceOverridden
                ? String(localized: "当前在「\(name)」，但你已手动恢复自动锁定，离开该网络前不再暂停。")
                : String(localized: "当前在「\(name)」，自动锁定已暂停。")
        }
        return String(localized: "当前不在任何信任场所，自动锁定正常工作。")
    }

    private var statusTint: Color {
        settings.activeTrustedPlaceName != nil && settings.trustedPlaceEnabled && !settings.trustedPlaceOverridden
            ? WLColor.warning : Color.secondary
    }

    // MARK: - 当前网络

    private var currentNetworkCard: some View {
        let snapshot = session.trustedPlaces.snapshot
        let check = TrustedPlace.canSave(snapshot, existing: settings.trustedPlaces)
        return VStack(alignment: .leading, spacing: WLSpacing.sm) {
            CardSectionHeader(title: String(localized: "当前网络"), systemImage: "wifi", tint: Color.primary)
            Text(describe(snapshot))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let hint = hint(for: check) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: WLSpacing.sm) {
                TextField("名称（可选）", text: $newName)
                    .textFieldStyle(.roundedBorder)
                WLButton(String(localized: "设为信任场所"), systemImage: "plus.circle", isDisabled: check != .ok) {
                    save()
                }
                .fixedSize(horizontal: true, vertical: false)
                .help("把当前网络加入信任场所；之后连接到它时会暂停自动锁定")
            }
            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
    }

    private func describe(_ snapshot: TrustedPlace.Snapshot) -> String {
        guard let mac = snapshot.gatewayMAC else { return String(localized: "未联网，或还没有读到网关信息") }
        if let ssid = snapshot.ssid, !ssid.isEmpty {
            return String(localized: "\(ssid) · 网关 \(mac)")
        }
        return String(localized: "网关 \(mac)")
    }

    private func hint(for check: TrustedPlace.SaveCheck) -> String? {
        switch check {
        case .ok: return nil
        case .offline: return String(localized: "联网后才能保存。")
        case .alreadySaved(let name): return String(localized: "这个网络已保存为「\(name)」。")
        }
    }

    private func save() {
        let result = session.saveCurrentNetworkAsTrustedPlace(name: newName)
        switch result {
        case .ok:
            newName = ""
            saveMessage = String(localized: "已保存。")
        case .offline:
            saveMessage = String(localized: "联网后才能保存。")
        case .alreadySaved(let name):
            saveMessage = String(localized: "这个网络已保存为「\(name)」。")
        }
    }

    // MARK: - 已保存的场所

    @ViewBuilder
    private var placesCard: some View {
        if !settings.trustedPlaces.isEmpty {
            VStack(alignment: .leading, spacing: WLSpacing.sm) {
                CardSectionHeader(title: String(localized: "已保存的场所"), systemImage: "mappin.and.ellipse", tint: Color.primary)
                ForEach(Array(settings.trustedPlaces.enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: WLSpacing.md) {
                        VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                            Text(place.name)
                            Text(placeSubtitle(place))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: WLSpacing.sm)
                        if session.trustedPlaces.current?.id == place.id {
                            Text("当前")
                                .font(.caption)
                                .foregroundStyle(WLColor.success)
                        }
                        WLButton(String(localized: "删除"), systemImage: "trash", role: .danger) {
                            placeToDelete = place
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .help("删除后，在该网络里将恢复自动锁定")
                    }
                    if index < settings.trustedPlaces.count - 1 { CardDivider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wlCard()
        }
    }

    private func placeSubtitle(_ place: TrustedPlace.Place) -> String {
        if let ssid = place.ssid, !ssid.isEmpty, ssid != place.name {
            return String(localized: "\(ssid) · 网关 \(place.gatewayMAC)")
        }
        return String(localized: "网关 \(place.gatewayMAC)")
    }
}

/// Wi-Fi 名称（定位授权）：可选增强，不授权也能用。
private struct WiFiNameCard: View {
    @ObservedObject var access: WiFiNameAccess

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            HStack(spacing: WLSpacing.sm) {
                CardSectionHeader(title: String(localized: "Wi-Fi 名称（可选）"), systemImage: "location", tint: Color.primary)
                Spacer(minLength: WLSpacing.sm)
                Text(access.state.title)
                    .font(.caption)
                    .foregroundStyle(access.state == .authorized ? WLColor.success : Color.secondary)
            }
            Text("信任场所靠网关识别网络，不需要任何授权。macOS 把 Wi-Fi 名称归在「定位服务」下，授权后列表里能显示网络名，并在「网关相同但换了 Wi-Fi 名称」时不再信任。WatchLock 不读取、不上传你的位置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if access.state == .notDetermined {
                WLButton(String(localized: "授权读取 Wi-Fi 名称…"), systemImage: "location") {
                    access.requestAuthorization()
                }
                .fixedSize(horizontal: true, vertical: false)
                .help("弹出系统的定位授权窗口")
            } else if access.state == .denied || access.state == .servicesDisabled {
                WLButton(String(localized: "打开系统设置"), systemImage: "gearshape") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .help("在「隐私与安全性 → 定位服务」里允许 WatchLock")
            }
            Text("重新打包安装后，系统可能要求重新授权；没有授权时功能照常工作，只是看不到网络名称。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
        .onAppear { access.refresh() }
    }
}
