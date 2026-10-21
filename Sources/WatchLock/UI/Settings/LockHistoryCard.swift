import AppKit
import SwiftUI

/// 诊断页的「锁定记录」卡（FR-21）：最近几次锁定的时间 · 原因 · 信号，支持导出 CSV 与清空。
///
/// 卡片只显示最近 `visibleCount` 条，完整记录（最多 200 条）通过导出查看，
/// 这样诊断页仍然是单一滚动区（日志区），不产生嵌套滚动。
struct LockHistoryCard: View {
    @ObservedObject private var history = LockHistoryStore.shared

    @State private var confirmingClear = false

    private let visibleCount = 4

    private var recent: [LockHistory.Record] {
        Array(history.records.suffix(visibleCount).reversed())
    }

    var body: some View {
        FormCard(
            title: String(localized: "锁定记录"),
            subtitle: String(localized: "每次实际执行的锁定都会留一条（含手动锁定），只保存在本机，最多 200 条。")
        ) {
            if history.records.isEmpty {
                Text("还没有锁定记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: WLSpacing.xs) {
                    ForEach(recent) { record in
                        row(record)
                    }
                }
                if history.records.count > visibleCount {
                    Text("仅显示最近 \(visibleCount) 条，共 \(history.records.count) 条；导出可查看全部。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: WLSpacing.sm) {
                WLButton(String(localized: "导出 CSV…"), isDisabled: history.records.isEmpty, width: 100) { export() }
                    .fixedSize(horizontal: true, vertical: false)
                    .help("导出全部锁定记录，便于核对或留档")
                WLButton(String(localized: "清空记录"), role: .danger, isDisabled: history.records.isEmpty, width: 100) {
                    confirmingClear = true
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
        }
        .confirmationDialog("清空全部锁定记录？", isPresented: $confirmingClear) {
            Button("清空", role: .destructive) { history.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ record: LockHistory.Record) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: WLSpacing.sm) {
            Text(LastLockSummary.text(reason: record.reason, at: record.date))
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if record.markedFalse {
                Text("误锁")
                    .font(.caption)
                    .foregroundStyle(WLColor.warning)
            } else {
                Text(record.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let rssi = record.rssi {
                Text("\(rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "watchlock-lock-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? LockHistory.csv(history.records).write(to: url, atomically: true, encoding: .utf8)
    }
}
