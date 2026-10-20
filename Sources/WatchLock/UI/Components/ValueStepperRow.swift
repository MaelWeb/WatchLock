import SwiftUI

/// 「标签 … 数值 + 步进器」一行，用于设置页的数值项。
///
/// 数值放在右侧、等宽数字，与系统设置里的步进行一致；原先把数字嵌在标签句子里
/// （「离开后等待 5 秒再锁定」），多行并排时数字上下不对齐，也无法和阈值带图例对应。
///
/// - `marker`：标签前的小圆点，用来和阈值带上同色的把手对应（在身边 = 绿、已离开 = 橙）。
/// - 步进器本身隐藏文字标签，但仍保留给 VoiceOver：标签 = `title`，值 = `valueText`。
struct ValueStepperRow<Value: Strideable>: View where Value.Stride: SignedNumeric {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    var step: Value.Stride = 1
    let valueText: String
    var marker: Color?
    var help: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: WLSpacing.sm) {
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
                    .accessibilityValue(valueText)
            }
        } label: {
            HStack(spacing: WLSpacing.sm) {
                if let marker {
                    Circle()
                        .fill(marker)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .help(help ?? "")
    }
}

/// 数值项的显示文案（带单位）。集中放这里，避免各页各写一份。
enum ValueFormat {
    static func dBm(_ value: Int) -> String { String(localized: "\(value) dBm") }
    static func seconds(_ value: Double) -> String { String(localized: "\(Int(value)) 秒") }
    static func minutes(_ value: Int) -> String { String(localized: "\(value) 分钟") }
}
