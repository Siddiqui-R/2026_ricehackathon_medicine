import Foundation

final class LocalRepository {
    let directory: URL
    var attachmentDirectory: URL { directory.appendingPathComponent("attachments", isDirectory: true) }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var backupURL: URL { directory.appendingPathComponent("state.backup.json") }
    init(directory: URL) {
        self.directory = directory
    }
    func load() throws -> (snapshot: AppSnapshot, recovered: Bool)? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        do { return (try decode(stateURL), false) }
        catch {
            if let backup = try? decode(backupURL) { return (backup, true) }
            throw RevaError.invalid("Saved data could not be opened. Your files are preserved. Retry, or explicitly reset the fictional demo in Settings.")
        }
    }
    private func decode(_ url: URL) throws -> AppSnapshot {
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url)); try snapshot.validate(); return snapshot
    }
    func save(_ snapshot: AppSnapshot) throws {
        try snapshot.validate()
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        if let old = try? Data(contentsOf: stateURL), (try? JSONDecoder().decode(AppSnapshot.self, from: old).validate()) != nil { try old.write(to: backupURL, options: .atomic) }
        try data.write(to: stateURL, options: .atomic)
    }
    func storeAttachment(_ data: Data, filename: String) throws -> URL {
        guard AppSnapshot.safeFilename(filename), data.count <= 16 * 1024 * 1024 else { throw RevaError.invalid("The attachment is invalid or larger than 16 MB.") }
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let url = attachmentDirectory.appendingPathComponent(filename); try data.write(to: url, options: .atomic); return url
    }
    func attachment(_ filename: String) -> URL? {
        guard AppSnapshot.safeFilename(filename) else { return nil }
        let url = attachmentDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
