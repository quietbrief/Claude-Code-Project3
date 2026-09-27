import SwiftUI
import WidgetKit

struct StaticEntry: TimelineEntry {
    let date: Date
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

/// A watch-face complication. Tapping it opens the watch app with a URL that
/// immediately triggers the call, so escaping takes a single tap.
struct TriggerComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let style: String
    let icon: String
    let title: String

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack {
                    Image(systemName: icon).font(.title3)
                    VStack(alignment: .leading) {
                        Text(title).font(.headline)
                        Text("轻点即来电").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            case .accessoryInline:
                Label(title, systemImage: icon)
            case .accessoryCorner:
                Image(systemName: icon).font(.title2)
                    .widgetLabel(title)
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: icon).font(.title2)
                }
            }
        }
        .widgetURL(URL(string: "fakecall-watch://trigger?style=\(style)"))
        .containerBackground(.clear, for: .widget)
    }
}

struct IPhoneCallComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FakeCallIPhone", provider: StaticProvider()) { _ in
            TriggerComplicationView(style: "iphone", icon: "phone.fill", title: "iPhone 来电")
        }
        .configurationDisplayName("iPhone 来电")
        .description("轻点后 iPhone 响起电话来电。")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct WeChatCallComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FakeCallWeChat", provider: StaticProvider()) { _ in
            TriggerComplicationView(style: "wechat", icon: "message.fill", title: "微信来电")
        }
        .configurationDisplayName("微信来电")
        .description("轻点后 iPhone 响起微信语音来电。")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct FakeCallComplications: WidgetBundle {
    var body: some Widget {
        IPhoneCallComplication()
        WeChatCallComplication()
    }
}
