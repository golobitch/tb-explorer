import AppKit
import SwiftUI
import TBKit
import UniformTypeIdentifiers

/// What the user chose in the save panel.
struct ExportChoice {
    let url: URL
    let format: ExportFormat
    let includeFormatted: Bool
}

/// The save panel, with the format and the formatted-columns switch in its accessory view so the
/// whole export is one dialog.
@MainActor
enum ExportPanel {
    static let formatKey = "export.format"
    static let formattedKey = "export.formatted"

    static var format: ExportFormat {
        get { UserDefaults.standard.string(forKey: formatKey).flatMap(ExportFormat.init) ?? .csv }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: formatKey) }
    }

    /// Off unless the user asks: an export is for machines first, and the exact integers are the
    /// part that has to be right.
    static var includeFormatted: Bool {
        get { UserDefaults.standard.bool(forKey: formattedKey) }
        set { UserDefaults.standard.set(newValue, forKey: formattedKey) }
    }

    static func run(suggestedName: String) async -> ExportChoice? {
        let panel = NSSavePanel()
        panel.title = "Export"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let options = ExportOptions()
        panel.accessoryView = NSHostingView(rootView: ExportOptionsView(options: options))
        panel.accessoryView?.frame.size = NSSize(width: 420, height: 92)

        // The format drives the panel's type, so the extension follows the choice.
        options.onFormatChange = { [weak panel] format in
            guard let panel else { return }
            panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
        }
        panel.allowedContentTypes = [options.format == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = "\(suggestedName).\(options.format.fileExtension)"

        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        format = options.format
        includeFormatted = options.includeFormatted
        return ExportChoice(url: url, format: options.format, includeFormatted: options.includeFormatted)
    }
}

@MainActor
@Observable
final class ExportOptions {
    var format: ExportFormat = ExportPanel.format {
        didSet { onFormatChange?(format) }
    }
    var includeFormatted = ExportPanel.includeFormatted

    @ObservationIgnored var onFormatChange: ((ExportFormat) -> Void)?
}

private struct ExportOptionsView: View {
    @Bindable var options: ExportOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Format", selection: $options.format) {
                Text("CSV").tag(ExportFormat.csv)
                Text("JSON").tag(ExportFormat.json)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Toggle("Include formatted columns", isOn: $options.includeFormatted)
            Text("Amounts and ids are always written exactly. Formatted columns are extra, and only for ledgers with a currency or an override.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(width: 420, alignment: .leading)
    }
}
