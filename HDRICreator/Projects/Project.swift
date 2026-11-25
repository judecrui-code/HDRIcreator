import Foundation

enum ProjectStatus: String, Codable {
    case capturing, captured, processing, complete, failed
    var label: String {
        switch self {
        case .capturing: return "Capturing"
        case .captured: return "Ready to process"
        case .processing: return "Processing"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
}

struct Project: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var created: Date
    var status: ProjectStatus
    var capturedIDs: [Int]            // target ids with a photo on disk
    var skippedIDs: [Int]
    var horizontalFOV: Double
    var exportWidth: Int?             // set after an EXR export
    var exportFile: String?

    static func new(name: String, fov: Double) -> Project {
        Project(id: UUID(), name: name, created: Date(), status: .capturing, capturedIDs: [], skippedIDs: [], horizontalFOV: fov, exportWidth: nil, exportFile: nil)
    }
    var resolutionLabel: String { exportWidth.map { "\($0)×\($0 / 2)" } ?? "—" }
}
