import SwiftUI

/// Browse any API response as a tree, or as pretty-printed text.
struct JSONInspectorView: View {
    let title: String
    let json: JSON
    @State private var showRaw = false

    var body: some View {
        Group {
            if showRaw {
                ScrollView([.vertical, .horizontal]) {
                    Text(json.prettyString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
            } else {
                List { JSONNodeRows(json: json) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showRaw.toggle() } label: { Image(systemName: showRaw ? "list.bullet.indent" : "curlybraces") }
                ShareLink(item: json.prettyString) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}

struct JSONNodeRows: View {
    let json: JSON

    var body: some View {
        switch json {
        case .object(let o):
            ForEach(o.keys.sorted(), id: \.self) { key in row(key, o[key] ?? .null) }
        case .array(let a):
            ForEach(Array(a.enumerated()), id: \.offset) { i, v in row("[\(i)]", v) }
        default:
            Text(json.displayString).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func row(_ key: String, _ value: JSON) -> some View {
        if value.isContainer {
            NavigationLink {
                JSONInspectorView(title: key, json: value)
            } label: {
                LabeledContent(key, value: value.displayString).font(.system(.callout, design: .monospaced))
            }
        } else {
            LabeledContent {
                Text(value.displayString).textSelection(.enabled).multilineTextAlignment(.trailing).foregroundStyle(color(value))
            } label: {
                Text(key)
            }
            .font(.system(.callout, design: .monospaced))
            .contextMenu { Button("Kopieer waarde") { UIPasteboard.general.string = value.displayString } }
        }
    }

    private func color(_ v: JSON) -> Color {
        switch v {
        case .string: return .green
        case .number: return .blue
        case .bool: return .purple
        default: return .secondary
        }
    }
}
