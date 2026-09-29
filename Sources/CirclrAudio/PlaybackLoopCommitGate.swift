import Foundation

/// Revocation and the short worker-pipe submission share one commit point.
/// An edit can discard staged PCM; it cannot revoke PCM already submitted to the scheduler.
public final class PlaybackLoopCommitGate:@unchecked Sendable {
    private let lock=NSLock()
    private var valid=true
    public init() {}
    public func invalidate() {lock.lock();valid=false;lock.unlock()}
    func submit(_ action:() throws -> Void)throws {
        lock.lock();defer{lock.unlock()}
        guard valid else {throw PlaybackTransportError.busy}
        try action()
    }
}
