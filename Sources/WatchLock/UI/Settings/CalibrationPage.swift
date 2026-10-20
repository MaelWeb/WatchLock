import SwiftUI

/// 校准页：距离校准向导 + 手动距离模型（原「高级」前半部分）。
struct CalibrationPage: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        SettingsDetail {
            VStack(alignment: .leading, spacing: WLSpacing.md) {
                CalibrationWizardView()

                FormCard(
                    title: String(localized: "距离模型（手动）"),
                    subtitle: String(localized: "自动校准通常够用；只有在估算距离明显偏离时才需要微调。")
                ) {
                    // 不用 `ValueStepperRow`：它基于 `LabeledContent`，只在 `Form` 里才左右分列，
                    // 放在 `FormCard`（普通 VStack）里会整体居中。
                    HStack(spacing: WLSpacing.sm) {
                        Text("1 米处标定值")
                        Spacer(minLength: WLSpacing.sm)
                        Text(ValueFormat.dBm(settings.measuredPower))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("1 米处标定值", value: $settings.measuredPower, in: -90 ... -30, step: 1)
                            .labelsHidden()
                            .accessibilityValue(ValueFormat.dBm(settings.measuredPower))
                    }
                    .font(.callout)
                    .help("手表在离 Mac 约 1 米处的平均信号强度")
                    // 用 Grid 让两行滑块左右对齐：标签宽度不同时，各自的 HStack 会把滑块起点错开。
                    Grid(alignment: .leading, horizontalSpacing: WLSpacing.sm, verticalSpacing: WLSpacing.sm) {
                        sliderRow(String(localized: "路径损耗指数"), value: $settings.pathLossExponent,
                                  range: 1.5 ... 4.0, step: 0.1, format: "%.1f")
                        sliderRow(String(localized: "平滑系数"), value: $settings.smoothing,
                                  range: 0.05 ... 1.0, step: 0.05, format: "%.2f")
                    }
                    .frame(maxWidth: .infinity)
                    Text("路径损耗指数越大表示信号衰减越快；平滑系数越小，距离显示越稳但响应越慢。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        GridRow {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .font(.callout)
    }
}
