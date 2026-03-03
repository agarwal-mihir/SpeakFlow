import Foundation
import Infra

public final class SingleInstanceLock {
    private var fd: Int32 = -1
    private let lockURL: URL

    public init(lockURL: URL = SpeakFlowPaths.appSupport.appendingPathComponent("speakflow.lock")) {
        self.lockURL = lockURL
    }

    public func acquire() -> Bool {
        try? ensureAppSupportDirectories()
        fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false
        }
        return true
    }

    deinit {
        if fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }
}
