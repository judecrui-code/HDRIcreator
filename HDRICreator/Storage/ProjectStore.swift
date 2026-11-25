import Foundation
import UIKit

/// On-disk layout:  Documents/Projects/<uuid>/{project.json, shots/shot_NN.heic, thumb.jpg, exports/*.exr}
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var storageBytes: Int64 = 0
    private let fm = FileManager.default

    static var root: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func folder(_ p: Project) -> URL { Self.root.appendingPathComponent(p.id.uuidString, isDirectory: true) }
    func shotsFolder(_ p: Project) -> URL { folder(p).appendingPathComponent("shots", isDirectory: true) }
    func exportsFolder(_ p: Project) -> URL { folder(p).appendingPathComponent("exports", isDirectory: true) }
    func shotURL(_ p: Project, id: Int) -> URL { shotsFolder(p).appendingPathComponent(String(format: "shot_%02d.heic", id)) }
    func thumbURL(_ p: Project) -> URL { folder(p).appendingPathComponent("thumb.jpg") }

    func reload() {
        let dirs = (try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        var list: [Project] = []
        for d in dirs {
            if let data = try? Data(contentsOf: d.appendingPathComponent("project.json")),
               let p = try? JSONDecoder.iso.decode(Project.self, from: data) { list.append(p) }
        }
        projects = list.sorted { $0.created > $1.created }
        storageBytes = directorySize(Self.root)
    }

    @discardableResult
    func create(name: String? = nil, fov: Double) throws -> Project {
        let p = Project.new(name: name ?? "HDRI " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short), fov: fov)
        try fm.createDirectory(at: shotsFolder(p), withIntermediateDirectories: true)
        try fm.createDirectory(at: exportsFolder(p), withIntermediateDirectories: true)
        try save(p)
        return p
    }

    func save(_ p: Project) throws {
        try fm.createDirectory(at: folder(p), withIntermediateDirectories: true)
        let data = try JSONEncoder.iso.encode(p)
        try data.write(to: folder(p).appendingPathComponent("project.json"), options: .atomic)
        if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = p } else { projects.insert(p, at: 0) }
    }

    func rename(_ p: Project, to name: String) { var q = p; q.name = name; try? save(q) }

    func delete(_ p: Project) {
        try? fm.removeItem(at: folder(p))
        projects.removeAll { $0.id == p.id }
        storageBytes = directorySize(Self.root)
    }

    func writeShot(_ data: Data, project: Project, id: Int) throws {
        try fm.createDirectory(at: shotsFolder(project), withIntermediateDirectories: true)
        try data.write(to: shotURL(project, id: id), options: .atomic)
        if let img = UIImage(data: data), let t = img.preparingThumbnail(of: CGSize(width: 240, height: 240))?.jpegData(compressionQuality: 0.7) {
            try? t.write(to: thumbURL(project))
        }
    }

    func refreshStorage() { storageBytes = directorySize(Self.root) }

    private func directorySize(_ url: URL) -> Int64 {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e { total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
        return total
    }
}

extension JSONEncoder { static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
