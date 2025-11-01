import Foundation

// MARK: - Binary Patch Set

/// A collection of binary patches organized together with metadata
struct BinaryPatchSet: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String?
    var author: String?
    var patches: [BinaryPatch]
    var status: Status
    var targetPath: String?
    var targetUUID: UUID?
    var targetArchitecture: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var auditLog: [BinaryPatchAuditEntry]
    
    enum Status: String, Codable {
        case draft
        case ready
        case applied
        case verified
        case failed
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        author: String? = nil,
        patches: [BinaryPatch] = [],
        status: Status = .draft,
        targetPath: String? = nil,
        targetUUID: UUID? = nil,
        targetArchitecture: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        auditLog: [BinaryPatchAuditEntry] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.patches = patches
        self.status = status
        self.targetPath = targetPath
        self.targetUUID = targetUUID
        self.targetArchitecture = targetArchitecture
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.auditLog = auditLog
    }
}

// MARK: - Binary Patch

/// Represents a single binary patch with original and patched byte sequences
struct BinaryPatch: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String?
    var fileOffset: UInt64
    var originalBytes: Data
    var patchedBytes: Data
    var enabled: Bool
    var status: Status
    var verificationMessage: String?
    var expectedUUID: UUID?
    var expectedArchitecture: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    
    enum Status: String, Codable {
        case pending
        case verified
        case failed
        case applied
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        fileOffset: UInt64,
        originalBytes: Data,
        patchedBytes: Data,
        enabled: Bool = true,
        status: Status = .pending,
        verificationMessage: String? = nil,
        expectedUUID: UUID? = nil,
        expectedArchitecture: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.fileOffset = fileOffset
        self.originalBytes = originalBytes
        self.patchedBytes = patchedBytes
        self.enabled = enabled
        self.status = status
        self.verificationMessage = verificationMessage
        self.expectedUUID = expectedUUID
        self.expectedArchitecture = expectedArchitecture
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Binary Patch Audit Entry

/// Audit log entry for tracking changes to patch sets and patches
struct BinaryPatchAuditEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let user: String?
    let event: EventType
    let patchID: UUID?
    let details: String
    let metadata: [String: String]
    
    enum EventType: String, Codable {
        case created
        case updated
        case deleted
        case applied
        case verified
        case enabled
        case disabled
    }
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        user: String? = nil,
        event: EventType,
        patchID: UUID? = nil,
        details: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.user = user
        self.event = event
        self.patchID = patchID
        self.details = details
        self.metadata = metadata
    }
}

// MARK: - Patch Template

/// A template for common patching scenarios with step-by-step instructions
struct PatchTemplate: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let category: Category
    let difficulty: Difficulty
    let icon: String
    let instructions: [TemplateInstruction]
    let tags: [String]
    
    enum Category: String, Codable, CaseIterable {
        case security = "Security"
        case performance = "Performance"
        case debugging = "Debugging"
        case compatibility = "Compatibility"
        case customization = "Customization"
        case reverseEngineering = "Reverse Engineering"
        
        var icon: String {
            switch self {
            case .security:
                return "lock.shield"
            case .performance:
                return "speedometer"
            case .debugging:
                return "ant"
            case .compatibility:
                return "checkmark.seal"
            case .customization:
                return "slider.horizontal.3"
            case .reverseEngineering:
                return "wrench.and.screwdriver"
            }
        }
    }
    
    enum Difficulty: String, Codable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: Category,
        difficulty: Difficulty,
        icon: String,
        instructions: [TemplateInstruction],
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.difficulty = difficulty
        self.icon = icon
        self.instructions = instructions
        self.tags = tags
    }
}

// MARK: - Template Instruction

/// A single step in a patch template with detailed instructions
struct TemplateInstruction: Codable, Identifiable {
    let id: UUID
    let step: Int
    let title: String
    let detail: String
    let arm64Pattern: String?
    let example: String?
    
    init(
        id: UUID = UUID(),
        step: Int,
        title: String,
        detail: String,
        arm64Pattern: String? = nil,
        example: String? = nil
    ) {
        self.id = id
        self.step = step
        self.title = title
        self.detail = detail
        self.arm64Pattern = arm64Pattern
        self.example = example
    }
}
