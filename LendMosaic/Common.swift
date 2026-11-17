import SwiftUI
import Observation
import UniformTypeIdentifiers

enum Languages {
    static let codes = ["en", "ja", "ko", "es", "fr", "de", "pt-BR", "it"]
    static let names = ["English", "日本語", "한국어", "Español", "Français", "Deutsch", "Português (Brasil)", "Italiano"]
    static func resolve(_ selection: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if codes.contains(selection) { return selection }
        for candidate in preferred {
            if candidate.hasPrefix("pt") { return "pt-BR" }
            if let code = codes.first(where: { candidate == $0 || candidate.hasPrefix($0 + "-") }) { return code }
        }
        return "en"
    }
    static var current: String { resolve(UserDefaults.standard.string(forKey: "language") ?? "system") }
}
func translated(_ key: String, language: String = Languages.current) -> String {
    guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
}
func number(_ value: Double, digits: Int = 1) -> String {
    value.formatted(.number.locale(Locale(identifier: Languages.current)).precision(.fractionLength(0...digits)))
}
func decimal(_ input: String) -> Double? {
    let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
    let localSeparator=Locale(identifier:Languages.current).decimalSeparator ?? "."
    let separator=(localSeparator != "." && text.contains(".") && !text.contains(localSeparator)) ? ".":localSeparator
    let escaped=NSRegularExpression.escapedPattern(for:separator)
    guard text.range(of:"^[+-]?[0-9]+(?:"+escaped+"[0-9]+)?$",options:.regularExpression) != nil,
          let value=Double(text.replacingOccurrences(of:separator,with:".")),value.isFinite else{return nil}
    return value
}
struct Words: View {
    let key: String
    init(_ key: String) { self.key = key }
    @Environment(\.locale) private var locale
    var body: some View { Text(verbatim: translated(key, language: locale.identifier)) }
}
enum Design {
    static let accent = Color("AccentColor")
    static let secondary = Color("SecondaryText")
    static let danger = Color("DangerText")
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.12)
    static let spacing: CGFloat = 20
}
struct EmptyRecords: View {
    var search = false
    var body: some View {
        ContentUnavailableView { Label { Words(search ? "No matching records" : "No records yet") } icon: { Image(systemName: "tray") } } description: { if !search { Words("Create your first record to get started.").foregroundStyle(Design.secondary) } }
    }
}
struct Metric: View {
    let title: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Words(title).font(.caption).foregroundStyle(Design.secondary); Text(verbatim: value).font(.title2.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine) }
}
struct JSONExport: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
@Observable @MainActor final class Repository<Value: Codable> {
    private(set) var value: Value
    private(set) var readFailed = false
    var error: String?
    let url: URL
    init(initial: Value, url: URL? = nil) {
        self.value = initial
        self.url = url ?? URL.documentsDirectory.appending(path: "records.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { value = try JSONDecoder().decode(Value.self, from: Data(contentsOf: self.url)) }
            catch { readFailed = true; self.error = "Unable to read records. Restore the data file before editing." }
        }
    }
    @discardableResult func update(_ newValue: Value) -> Bool {
        guard !readFailed else { error = "Unable to read records. Restore the data file before editing."; return false }
        do {
            let data = try JSONEncoder().encode(newValue)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            value = newValue
            return true
        } catch { self.error = "Unable to save. Your existing records are unchanged."; return false }
    }
    func encoded() throws -> Data { try JSONEncoder().encode(value) }
}
struct SettingsView: View {
    let appName: String
    let canSeed: Bool
    let seed: () -> Void
    let export: () throws -> Data
    @AppStorage("language") private var language = "system"
    @AppStorage("appearance") private var appearance = "system"
    @State private var showExport = false
    @State private var document = JSONExport(data: Data())
    @State private var exportError = false
    var body: some View {
        Form {
            Section {
                Picker(selection: $language) { Words("System").tag("system"); ForEach(Array(zip(Languages.codes, Languages.names)), id: \.0) { Text(verbatim: $0.1).tag($0.0) } } label: { Words("Language") }.accessibilityIdentifier("languagePicker")
                Picker(selection: $appearance) { ForEach(["system", "light", "dark"], id: \.self) { Words($0.capitalized).tag($0) } } label: { Words("Appearance") }.accessibilityIdentifier("appearancePicker")
            }
            Section { Button { do { document = JSONExport(data: try export()); showExport = true } catch { exportError = true } } label: { Label { Words("Export records") } icon: { Image(systemName: "square.and.arrow.up") } } }
            Section { Button(action: seed) { Words("Load sample data") }.disabled(!canSeed).accessibilityIdentifier("sampleData"); Words("Only available when your collection is empty.").font(.footnote).foregroundStyle(Design.secondary) }
            Section { NavigationLink { VStack(alignment: .leading, spacing: 24) { Words("Records stay on this device. No account, ads or purchases."); Spacer() }.padding(24).navigationTitle(Text(LocalizedStringKey("Privacy"))) } label: { Words("Privacy") }.accessibilityIdentifier("privacyLink")
                NavigationLink { VStack(spacing: 20) { Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(Design.accent); Text(verbatim: appName).font(.title); Words("Version 1.0"); Words("Records stay on this device. No account, ads or purchases.") }.padding().navigationTitle(Text(LocalizedStringKey("About"))) } label: { Words("About") }
            }
        }.scrollContentBackground(.hidden).background(AppBackground()).navigationTitle(Text(LocalizedStringKey("Settings"))).navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExport, document: document, contentType: .json, defaultFilename: appName + "-records") { result in if case .failure = result { exportError = true } }
        .alert(Text(LocalizedStringKey("Unable to save. Your existing records are unchanged.")), isPresented: $exportError) { Button("Done", role: .cancel) {} }
    }
}
struct Field: View {
    let key: String
    @Binding var value: String
    var numeric = false
    var identifier: String = ""
    var body: some View { VStack(alignment: .leading, spacing: 6) { Words(key).font(.caption).foregroundStyle(Design.secondary); TextField(LocalizedStringKey(key), text: $value).keyboardType(numeric ? .decimalPad : .default).accessibilityIdentifier(identifier.isEmpty ? key : identifier) } }
}
struct NumericField:View {
 let key:String;@Binding var value:Double
 @State private var text:String
 init(key:String,value:Binding<Double>){self.key=key;self._value=value;self._text=State(initialValue:value.wrappedValue.isFinite ? value.wrappedValue.formatted(.number.locale(Locale(identifier:Languages.current)).grouping(.never).precision(.fractionLength(0...12))):"")}
 var body:some View{VStack(alignment:.leading,spacing:6){Words(key).font(.caption).foregroundStyle(Design.secondary);TextField(LocalizedStringKey(key),text:$text).keyboardType(.decimalPad).accessibilityIdentifier(key).onChange(of:text){_,new in value=decimal(new) ?? .nan}}}
}
struct NotesBlock:View {let text:String;var body:some View{if !text.isEmpty{Section{Text(verbatim:text)}header:{Words("Notes").foregroundStyle(Design.secondary)}}}}
func dateText(_ date:Date)->String{date.formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier:Languages.current)))}
struct SectionHeading:View{let title:String;let subtitle:String;var body:some View{VStack(alignment:.leading,spacing:8){Words(title).font(.title.bold());Words(subtitle).foregroundStyle(Design.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}}
