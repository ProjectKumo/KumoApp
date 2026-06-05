import SwiftUI
import KumoCoreKit

struct SubStoreParserSection: View {
    @Environment(SubStoreStore.self) private var subStore

    @State private var input = ""
    @State private var output = ""
    @State private var platform = "ClashMeta"
    @State private var mode = Mode.proxy
    @State private var isParsing = false

    private enum Mode: String, CaseIterable {
        case proxy = "Proxy"
        case rule = "Rule"
    }

    private let platforms = [
        "ClashMeta", "Surge", "Loon", "QuantumultX",
        "Stash", "Shadowrocket", "Surfboard", "SingBox", "JSON",
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Form {
                Picker(String(localized: "Mode"), selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "Platform"), selection: $platform) {
                    ForEach(platforms, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }

                Section(String(localized: "Input")) {
                    TextEditor(text: $input)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                }

                Section(String(localized: "Output")) {
                    TextEditor(text: $output)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Protocol Parser"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if isParsing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                parse()
            } label: {
                Label(String(localized: "Parse"), systemImage: "play.fill")
            }
            .disabled(input.isEmpty || isParsing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func parse() {
        isParsing = true
        Task {
            defer { isParsing = false }
            switch mode {
            case .proxy:
                output = await subStore.parseProxies(data: input, platform: platform) ?? ""
            case .rule:
                output = await subStore.parseRules(data: input, platform: platform) ?? ""
            }
        }
    }
}
