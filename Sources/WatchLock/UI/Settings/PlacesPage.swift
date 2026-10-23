import SwiftUI

/// 场景页：信任场所（在家 / 办公室等已知网络里自动暂停自动锁定）。
///
/// 规则、依据与安全边界见 `TrustedPlace`。界面上要如实交代两件事：
/// 1. 网关地址可被同网络里的设备伪造，这是便利特性，不是安全边界；
/// 2. 定位授权是**可选**的：不授权时网络场所照常工作，只是不能按位置信任，也看不到 Wi-Fi 名称；
/// 3. 位置来自 Mac 的网络定位，精度有限，所以半径最小 100 米，精度不够时不会保存，也不会判为「在场所内」。
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
                LocationPlaceCard(
                    monitor: session.trustedPlaces,
                    access: session.trustedPlaces.wifiAccess
                )
                placesCard
                WiFiNameCard(access: session.trustedPlaces.wifiAccess)
                Text("网络指纹和位置只在本机比对，不上传。网络指纹可以被同一网络里的设备伪造，位置也可能因定位误差飘出范围，所以这是方便功能，不是安全防线；离开该场所后会立即恢复自动锁定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            session.trustedPlaces.requestLocation(force: true)
            session.trustedPlaces.refreshSnapshot()
        }
        .onReceive(refreshTimer) { _ in
            session.trustedPlaces.requestLocation()
            session.trustedPlaces.refreshSnapshot()
        }
        .confirmationDialog(
            "删除信任场所「\(placeToDelete?.name ?? "")」？",
            isPresented: Binding(get: { placeToDelete != nil }, set: { if !$0 { placeToDelete = nil } }),
            presenting: placeToDelete
        ) { place in
            Button("删除", role: .destructive) { session.removeTrustedPlace(id: place.id) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除后，在该场所里将恢复自动锁定。")
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
            .help("连接到你保存过的网络、或位于保存过的位置（如家里、办公室）时，不再自动锁屏")
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
                ? String(localized: "当前在「\(name)」，但你已手动恢复自动锁定，离开该场所前不再暂停。")
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
                        .help("删除后，在该场所里将恢复自动锁定")
                    }
                    if index < settings.trustedPlaces.count - 1 { CardDivider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wlCard()
        }
    }

    private func placeSubtitle(_ place: TrustedPlace.Place) -> String {
        if place.isLocationPlace, let radius = place.radius {
            return String(localized: "位置 · 半径 \(Int(radius)) 米")
        }
        let mac = place.gatewayMAC ?? ""
        if let ssid = place.ssid, !ssid.isEmpty, ssid != place.name {
            return String(localized: "\(ssid) · 网关 \(mac)")
        }
        return String(localized: "网关 \(mac)")
    }
}

/// 把当前位置保存为信任场所：解决「同一个地点换了网络」网关指纹失效的问题。
private struct LocationPlaceCard: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject var monitor: TrustedPlaceMonitor
    @ObservedObject var access: WiFiNameAccess

    @State private var radius = TrustedPlace.defaultRadius
    @State private var name = ""
    @State private var saveMessage: String?

    var body: some View {
        let fix = monitor.snapshot.location
        let check = TrustedPlace.canSaveLocation(fix, radius: radius, existing: settings.trustedPlaces)
        return VStack(alignment: .leading, spacing: WLSpacing.sm) {
            CardSectionHeader(title: String(localized: "当前位置"), systemImage: "location.circle", tint: Color.primary)
            if access.state == .authorized {
                Text(describe(fix))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = hint(for: check) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                controls(check: check)
            } else {
                unauthorized
            }
            Text("Mac 靠 Wi-Fi 和网络定位，精度通常几十到几百米，所以半径最小 100 米；定位不准或没有定位结果时，不会按位置判断「在场所内」。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
    }

    private func controls(check: TrustedPlace.LocationSaveCheck) -> some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            Picker("半径", selection: $radius) {
                ForEach(TrustedPlace.radiusChoices, id: \.self) { choice in
                    Text("\(Int(choice)) 米").tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .help("位于该位置半径内时视为在场所内；半径越大越不容易误判离开，但覆盖范围也越大")
            HStack(spacing: WLSpacing.sm) {
                TextField("名称（可选）", text: $name)
                    .textFieldStyle(.roundedBorder)
                WLButton(String(localized: "将当前位置设为信任场所"), systemImage: "plus.circle", isDisabled: check != .ok) {
                    save()
                }
                .fixedSize(horizontal: true, vertical: false)
                .help("把当前位置加入信任场所；位于该位置附近时会暂停自动锁定")
            }
            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var unauthorized: some View {
        Text("按位置信任需要定位授权。授权后可以把当前位置保存为信任场所；WatchLock 只在本机比对位置，不上传。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if access.state == .notDetermined {
            WLButton(String(localized: "授权定位服务…"), systemImage: "location") {
                access.requestAuthorization()
            }
            .fixedSize(horizontal: true, vertical: false)
            .help("弹出系统的定位授权窗口")
        } else {
            WLButton(String(localized: "打开系统设置"), systemImage: "gearshape") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .help("在「隐私与安全性 → 定位服务」里允许 WatchLock")
        }
    }

    private func describe(_ fix: TrustedPlace.LocationFix?) -> String {
        guard let fix, Date().timeIntervalSince(fix.timestamp) <= TrustedPlace.locationMaxAge else {
            return String(localized: "正在定位…")
        }
        return String(localized: "已定位 · 精度约 \(Int(fix.horizontalAccuracy)) 米")
    }

    private func hint(for check: TrustedPlace.LocationSaveCheck) -> String? {
        switch check {
        case .ok, .noFix: return nil
        case .inaccurate(let accuracy):
            return String(localized: "当前定位精度约 \(Int(accuracy)) 米，比所选半径还差，请选更大的半径或稍后再试。")
        case .alreadySaved(let name):
            return String(localized: "这个位置已在「\(name)」的范围内。")
        }
    }

    private func save() {
        switch session.saveCurrentLocationAsTrustedPlace(name: name, radius: radius) {
        case .ok:
            name = ""
            saveMessage = String(localized: "已保存。")
        case .noFix:
            saveMessage = String(localized: "还没有定位结果，请稍后再试。")
        case .inaccurate(let accuracy):
            saveMessage = String(localized: "当前定位精度约 \(Int(accuracy)) 米，比所选半径还差。")
        case .alreadySaved(let name):
            saveMessage = String(localized: "这个位置已在「\(name)」的范围内。")
        }
    }
}

/// Wi-Fi 名称（定位授权）：可选增强，不授权也能用。
private struct WiFiNameCard: View {
    @ObservedObject var access: WiFiNameAccess

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            HStack(spacing: WLSpacing.sm) {
                CardSectionHeader(title: String(localized: "定位服务（可选）"), systemImage: "location", tint: Color.primary)
                Spacer(minLength: WLSpacing.sm)
                Text(access.state.title)
                    .font(.caption)
                    .foregroundStyle(access.state == .authorized ? WLColor.success : Color.secondary)
            }
            Text("网络场所靠网关识别，不需要任何授权。授权定位服务后，可以把当前位置保存为信任场所，列表里也能显示 Wi-Fi 名称，并在「网关相同但换了 Wi-Fi 名称」时不再信任。位置只在本机比对，不上传。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if access.state == .notDetermined {
                WLButton(String(localized: "授权定位服务…"), systemImage: "location") {
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
            Text("重新打包安装后，系统可能要求重新授权；授权丢失时位置场所不会生效（按「不在场所内」处理），网络场所照常工作。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
        .onAppear { access.refresh() }
    }
}
