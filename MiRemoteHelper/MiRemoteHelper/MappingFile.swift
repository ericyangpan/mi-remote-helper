import SwiftUI
import UniformTypeIdentifiers

struct MappingFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw MappingDefinitionError.invalidDefinition }
        _ = try MappingDefinitionCodec.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }

    static func read(_ url: URL) throws -> MappingDefinition {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: MappingDefinitionCodec.maximumBytes + 1) ?? Data()
        return try MappingDefinitionCodec.decode(data)
    }
}
