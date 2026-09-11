import Foundation

/// A copied demo may replace only the exact workspace that requested it.
public struct DemoLoadTicket {
    public let generation: Int
    private let project: Project
    private let projectPath: String?
    private let mediaPath: String?
    public init(generation: Int, project: Project, projectPath: String?, mediaPath: String?) {
        self.generation = generation; self.project = project
        self.projectPath = projectPath; self.mediaPath = mediaPath
    }
    public func canApply(generation: Int, project: Project, projectPath: String?, mediaPath: String?, cancelled: Bool) -> Bool {
        !cancelled && generation == self.generation && project == self.project &&
            projectPath == self.projectPath && mediaPath == self.mediaPath
    }
}
