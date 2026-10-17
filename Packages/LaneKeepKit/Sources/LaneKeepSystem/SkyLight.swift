#if canImport(AppKit)
import CoreGraphics
import Foundation

/// The one window server call LaneKeep needs that macOS does not publish, looked up at run time in
/// SkyLight (the framework behind CoreGraphics' window functions), as window managers do. When a later
/// macOS drops or renames it, the answers are `nil` and LaneKeep behaves as it did without it.
enum SkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias WindowIsOrderedIn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Bool>) -> Int32

    private static let isOrderedInFunction: (connection: Int32, call: WindowIsOrderedIn)? = {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
            let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
            let isOrderedInSymbol = dlsym(handle, "SLSWindowIsOrderedIn")
        else {
            return nil
        }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnectionID.self)()
        return (connection, unsafeBitCast(isOrderedInSymbol, to: WindowIsOrderedIn.self))
    }()

    /// Whether the window is shown on its desktop ("ordered in"): `false` for a window its app keeps
    /// after it was closed, `nil` when the window server could not be asked.
    static func isOrderedIn(_ windowID: CGWindowID) -> Bool? {
        guard let function = isOrderedInFunction else {
            return nil
        }
        var value = false
        guard function.call(function.connection, windowID, &value) == 0 else {
            return nil
        }
        return value
    }
}
#endif
