import Foundation

/// Service for managing binary patch sets
/// Provides thread-safe operations for creating, updating, and applying patches to binary files
final class BinaryPatchService {
    static let shared = BinaryPatchService()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.jian.ReDyne.binaryPatchService", qos: .userInitiated)

    private var patchSets: [UUID: BinaryPatchSet] = [:]
    private var cacheLoaded = false

    private init() {}

    // MARK: - Public API
    
    /// Loads all patch sets from disk into memory
    /// This method is thread-safe and only loads once
    func loadPatchSets() {
        queue.sync {
            guard !cacheLoaded else { return }
            try? ensureStorageDirectory()
            loadFromDisk()
            cacheLoaded = true
        }
    }
    
    /// Returns all patch sets sorted by update date (newest first)
    /// - Returns: Array of patch sets
    func getAllPatchSets() -> [BinaryPatchSet] {
        queue.sync {
            patchSets.values.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    /// Retrieves a specific patch set by ID
    /// - Parameter id: UUID of the patch set
    /// - Returns: The patch set if found, nil otherwise
    func getPatchSet(with id: UUID) -> BinaryPatchSet? {
        queue.sync { patchSets[id] }
    }

    @discardableResult
    func createPatchSet(name: String, description: String? = nil, author: String? = nil) throws -> BinaryPatchSet {
        let patchSet = BinaryPatchSet(name: name, description: description, author: author)
        try addPatchSet(patchSet)
        return patchSet
    }

    func addPatchSet(_ patchSet: BinaryPatchSet) throws {
        try queue.sync {
            guard patchSets[patchSet.id] == nil else {
                throw BinaryPatchServiceError.duplicatePatchSet
            }
            var newPatchSet = patchSet
            try validatePatchSet(newPatchSet)
            recordAudit(&newPatchSet, event: .created, details: "Patch set \(newPatchSet.name) created")
            patchSets[newPatchSet.id] = newPatchSet
            try persistPatchSet(newPatchSet)
        }
    }

    func updatePatchSet(_ patchSet: BinaryPatchSet) throws {
        try queue.sync {
            guard patchSets[patchSet.id] != nil else {
                throw BinaryPatchServiceError.patchSetNotFound
            }
            try validatePatchSet(patchSet)
            var updatedPatchSet = patchSet
            updatedPatchSet.updatedAt = Date()
            recordAudit(&updatedPatchSet, event: .updated, details: "Patch set \(updatedPatchSet.name) updated")
            patchSets[updatedPatchSet.id] = updatedPatchSet
            try persistPatchSet(updatedPatchSet)
        }
    }

    func deletePatchSet(with id: UUID) throws {
        try queue.sync {
            guard patchSets.removeValue(forKey: id) != nil else {
                throw BinaryPatchServiceError.patchSetNotFound
            }
            try deletePatchSetFromDisk(id: id)
        }
    }

    func addPatch(_ patch: BinaryPatch, to patchSetID: UUID) throws {
        try queue.sync {
            guard var patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }
            guard !patchSet.patches.contains(where: { $0.id == patch.id }) else {
                throw BinaryPatchServiceError.duplicatePatch
            }

            try validatePatch(patch, in: patchSet)

            patchSet.patches.append(patch)
            recordAudit(
                &patchSet,
                event: .created,
                patchID: patch.id,
                details: "Patch \(patch.name) created"
            )

            patchSets[patchSetID] = patchSet
            try persistPatchSet(patchSet)
        }
    }

    func updatePatch(_ patch: BinaryPatch, in patchSetID: UUID) throws {
        try queue.sync {
            guard var patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }

            guard let index = patchSet.patches.firstIndex(where: { $0.id == patch.id }) else {
                throw BinaryPatchServiceError.patchNotFound
            }
            try validatePatch(patch, in: patchSet)

            patchSet.patches[index] = patch
            recordAudit(
                &patchSet,
                event: .updated,
                patchID: patch.id,
                details: "Patch \(patch.name) updated"
            )

            patchSets[patchSetID] = patchSet
            try persistPatchSet(patchSet)
        }
    }

    func deletePatch(withID patchID: UUID, in patchSetID: UUID) throws {
        try queue.sync {
            guard var patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }

            guard let index = patchSet.patches.firstIndex(where: { $0.id == patchID }) else {
                throw BinaryPatchServiceError.patchNotFound
            }

            let removedPatch = patchSet.patches.remove(at: index)
            recordAudit(
                &patchSet,
                event: .deleted,
                patchID: removedPatch.id,
                details: "Patch \(removedPatch.name) deleted"
            )

            patchSets[patchSetID] = patchSet
            try persistPatchSet(patchSet)
        }
    }

    func setPatchEnabled(_ enabled: Bool, patchID: UUID, in patchSetID: UUID, user: String? = nil) throws {
        try queue.sync {
            guard var patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }

            guard let index = patchSet.patches.firstIndex(where: { $0.id == patchID }) else {
                throw BinaryPatchServiceError.patchNotFound
            }

            var patch = patchSet.patches[index]
            guard patch.enabled != enabled else { return }

            patch.enabled = enabled
            patch.updatedAt = Date()
            patchSet.patches[index] = patch

            recordAudit(
                &patchSet,
                event: .updated,
                patchID: patchID,
                details: "Patch \(patch.name) \(enabled ? "enabled" : "disabled")",
                user: user
            )

            patchSets[patchSetID] = patchSet
            try persistPatchSet(patchSet)
        }
    }

    func updatePatchStatus(_ status: BinaryPatch.Status, patchID: UUID, in patchSetID: UUID, message: String? = nil) throws {
        try queue.sync {
            guard var patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }

            guard let index = patchSet.patches.firstIndex(where: { $0.id == patchID }) else {
                throw BinaryPatchServiceError.patchNotFound
            }

            var patch = patchSet.patches[index]
            patch.status = status
            patch.updatedAt = Date()
            patch.verificationMessage = message
            patchSet.patches[index] = patch

            recordAudit(
                &patchSet,
                event: .updated,
                patchID: patchID,
                details: "Patch \(patch.name) status changed to \(status.rawValue)",
                metadata: message == nil ? [:] : ["message": message ?? ""]
            )

            patchSets[patchSetID] = patchSet
            try persistPatchSet(patchSet)
        }
    }

    func updatePatchSetStatus(_ status: BinaryPatchSet.Status, for patchSetID: UUID, message: String? = nil) throws {
        try queue.sync {
            guard var patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }

            guard patchSet.status != status || message != nil else { return }

            patchSet.status = status
            recordAudit(
                &patchSet,
                event: .updated,
                details: "Patch set \(patchSet.name) status changed to \(status.rawValue)",
                metadata: message == nil ? [:] : ["message": message ?? ""]
            )

            patchSets[patchSetID] = patchSet
            try persistPatchSet(patchSet)
        }
    }

    func searchPatches(query: String, limit: Int = 50) -> [BinaryPatch] {
        guard !query.isEmpty else { return [] }
        return queue.sync {
            patchSets.values
                .flatMap { $0.patches }
                .filter { patch in
                    patch.name.localizedCaseInsensitiveContains(query) ||
                    (patch.description?.localizedCaseInsensitiveContains(query) ?? false) ||
                    patch.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                }
                .prefix(limit)
                .map { $0 }
        }
    }

    func searchPatchSets(query: String, limit: Int = 20) -> [BinaryPatchSet] {
        guard !query.isEmpty else { return [] }
        return queue.sync {
            patchSets.values
                .filter { patchSet in
                    patchSet.name.localizedCaseInsensitiveContains(query) ||
                    (patchSet.description?.localizedCaseInsensitiveContains(query) ?? false) ||
                    patchSet.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit)
                .map { $0 }
        }
    }

    func recentAuditEntries(limit: Int = 50) -> [BinaryPatchAuditEntry] {
        queue.sync {
            patchSets.values
                .flatMap { $0.auditLog }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(limit)
                .map { $0 }
        }
    }

    func exportPatchSet(_ patchSetID: UUID) throws -> Data {
        try queue.sync {
            guard let patchSet = patchSets[patchSetID] else {
                throw BinaryPatchServiceError.patchSetNotFound
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(patchSet)
        }
    }
    
    /// Imports a patch set from JSON data
    /// - Parameter data: JSON data containing the patch set
    /// - Throws: Error if decoding or adding the patch set fails
    func importPatchSet(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let patchSet = try decoder.decode(BinaryPatchSet.self, from: data)
        try addPatchSet(patchSet)
    }
    
    /// Gets statistics about all patch sets
    /// - Returns: Dictionary containing various statistics
    func getStatistics() -> [String: Int] {
        return queue.sync {
            let totalPatches = patchSets.values.reduce(0) { $0 + $1.patches.count }
            let enabledPatches = patchSets.values.reduce(0) { $0 + $1.patches.filter { $0.enabled }.count }
            let verifiedPatches = patchSets.values.reduce(0) { $0 + $1.patches.filter { $0.status == .verified }.count }
            
            return [
                "totalPatchSets": patchSets.count,
                "totalPatches": totalPatches,
                "enabledPatches": enabledPatches,
                "verifiedPatches": verifiedPatches
            ]
        }
    }
    
    /// Finds all patch sets targeting a specific binary
    /// - Parameter binaryPath: Path to the binary file
    /// - Returns: Array of matching patch sets
    func getPatchSets(forBinaryAt binaryPath: String) -> [BinaryPatchSet] {
        return queue.sync {
            let standardizedPath = URL(fileURLWithPath: binaryPath).standardizedFileURL.path
            return patchSets.values.filter { patchSet in
                guard let targetPath = patchSet.targetPath else { return false }
                let standardizedTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.path
                return standardizedTarget == standardizedPath
            }.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: - Validation

    private func validatePatchSet(_ patchSet: BinaryPatchSet) throws {
        if patchSet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BinaryPatchServiceError.invalidPatchSet(reason: "Name cannot be empty")
        }
        if patchSet.patches.isEmpty {
            return
        }
        for patch in patchSet.patches {
            try validatePatch(patch, in: patchSet)
        }
    }

    private func validatePatch(_ patch: BinaryPatch, in patchSet: BinaryPatchSet) throws {
        if patch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BinaryPatchServiceError.invalidPatch(reason: "Patch name cannot be empty")
        }
        if patch.patchedBytes.isEmpty {
            throw BinaryPatchServiceError.invalidPatch(reason: "Patched bytes cannot be empty")
        }
        if patch.originalBytes.isEmpty {
            throw BinaryPatchServiceError.invalidPatch(reason: "Original bytes cannot be empty")
        }
        if patch.originalBytes.count != patch.patchedBytes.count {
            throw BinaryPatchServiceError.invalidPatch(reason: "Original and patched bytes must be the same length")
        }
        if let expectedUUID = patch.expectedUUID, let targetUUID = patchSet.targetUUID, expectedUUID != targetUUID {
            throw BinaryPatchServiceError.invalidPatch(reason: "Patch target UUID mismatch")
        }
        if let expectedArch = patch.expectedArchitecture, let targetArch = patchSet.targetArchitecture, expectedArch != targetArch {
            throw BinaryPatchServiceError.invalidPatch(reason: "Patch target architecture mismatch")
        }
    }

    // MARK: - Persistence

    private func storageDirectoryURL() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documentsURL.appendingPathComponent(Constants.File.patchSetsDirectoryName, isDirectory: true)
    }

    private func ensureStorageDirectory() throws {
        let directoryURL = try storageDirectoryURL()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func patchSetFileURL(for id: UUID) throws -> URL {
        try storageDirectoryURL().appendingPathComponent("\(id.uuidString).json")
    }

    private func persistPatchSet(_ patchSet: BinaryPatchSet) throws {
        try ensureStorageDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(patchSet)
        let fileURL = try patchSetFileURL(for: patchSet.id)
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let directoryURL = try? storageDirectoryURL(),
              let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for fileURL in files where fileURL.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: fileURL)
                let patchSet = try decoder.decode(BinaryPatchSet.self, from: data)
                patchSets[patchSet.id] = patchSet
            } catch {
                ErrorHandler.log(error)
            }
        }
    }

    private func deletePatchSetFromDisk(id: UUID) throws {
        let fileURL = try patchSetFileURL(for: id)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Audit Helpers

    private func recordAudit(
        _ patchSet: inout BinaryPatchSet,
        event: BinaryPatchAuditEntry.EventType,
        patchID: UUID? = nil,
        details: String,
        metadata: [String: String] = [:],
        user: String? = nil
    ) {
        var mergedMetadata = metadata
        mergedMetadata["patchSetID"] = patchSet.id.uuidString
        if let patchID = patchID {
            mergedMetadata["patchID"] = patchID.uuidString
        }

        let entry = BinaryPatchAuditEntry(
            timestamp: Date(),
            user: user,
            event: event,
            patchID: patchID,
            details: details,
            metadata: mergedMetadata
        )

        patchSet.auditLog.append(entry)
        patchSet.updatedAt = Date()
    }
}

// MARK: - Errors

/// Errors that can occur during patch set operations
enum BinaryPatchServiceError: Error {
    case duplicatePatchSet
    case patchSetNotFound
    case duplicatePatch
    case patchNotFound
    case invalidPatchSet(reason: String)
    case invalidPatch(reason: String)
}

// MARK: - Error Extensions

extension BinaryPatchServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .duplicatePatchSet:
            return "A patch set with this ID already exists"
        case .patchSetNotFound:
            return "The requested patch set could not be found"
        case .duplicatePatch:
            return "A patch with this ID already exists in the patch set"
        case .patchNotFound:
            return "The requested patch could not be found in the patch set"
        case .invalidPatchSet(let reason):
            return "Invalid patch set: \(reason)"
        case .invalidPatch(let reason):
            return "Invalid patch: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .duplicatePatchSet:
            return "Use a different patch set ID or update the existing patch set"
        case .patchSetNotFound:
            return "Verify the patch set ID and ensure it has been loaded"
        case .duplicatePatch:
            return "Use a different patch ID or update the existing patch"
        case .patchNotFound:
            return "Verify the patch ID and patch set ID are correct"
        case .invalidPatchSet, .invalidPatch:
            return "Check the validation error details and correct the issue"
        }
    }
}
