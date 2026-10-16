import Foundation

/// Brings the app's workspaces together with changes another program made to `workspaces.json`
/// in the meantime: the `lanekeep` command saves workspaces into the same file, and the file may
/// have been edited by hand.
public enum WorkspaceMerge {
    /// - Parameters:
    ///   - local: The workspaces the app has.
    ///   - file: The workspaces in the file now.
    ///   - changedLocally: Workspaces the app added or changed since it last read or wrote the file.
    ///   - deletedLocally: Workspaces the app deleted since then.
    /// - Returns: The app's version of what the app changed and the file's version of everything
    ///   else, in the app's order, followed by the workspaces only the file has (unless the app
    ///   deleted them). Workspaces the app did not change and the file no longer has are dropped.
    public static func merge(
        local: [Workspace],
        file: [Workspace],
        changedLocally: Set<UUID>,
        deletedLocally: Set<UUID>
    ) -> [Workspace] {
        let fileByID = Dictionary(file.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [Workspace] = []
        var seen = Set<UUID>()
        for workspace in local where seen.insert(workspace.id).inserted {
            if changedLocally.contains(workspace.id) {
                merged.append(workspace)
            } else if let fromFile = fileByID[workspace.id] {
                merged.append(fromFile)
            }
        }
        for workspace in file where !deletedLocally.contains(workspace.id) && seen.insert(workspace.id).inserted {
            merged.append(workspace)
        }
        return merged
    }
}
