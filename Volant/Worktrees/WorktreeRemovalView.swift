import SwiftUI
import VolantCore

/// Asks before removing a git worktree: names the folder, its size, what happens to the branch and
/// to uncommitted work. Neither button is the default, so Return never removes anything; Escape or
/// Cancel closes it.
struct WorktreeRemovalView: View {
    @ObservedObject var model: LauncherModel
    let worktree: Worktree

    private var size: String? {
        model.worktrees.details[worktree.path].flatMap { info in info.size.map { Worktrees.formatSize($0, complete: info.sizeComplete) } }
    }
    private var changes: Int? { model.worktrees.changes[worktree.path] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove the worktree “\(worktree.name, format: .verbatim)”?").font(.headline)
            Text(Worktrees.abbreviate(worktree.path, home: WorktreesModel.home) + (size.map { " · " + $0 } ?? ""))
                .font(.subheadline.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            VStack(alignment: .leading, spacing: 6) {
                Text("Its folder is deleted. Git checks again first and stops if anything changed or is still running there.")
                if let branch = worktree.branch {
                    Text("The branch \(branch, format: .verbatim) stays in the repository.")
                } else {
                    Text("It isn’t on a branch. If it has commits no branch holds, nothing is removed.")
                }
                if let changes, changes > 0 {
                    Text("Its \(changes, specifier: "%lld") uncommitted changes are saved first, in Application Support › Volant › Worktree Backups.")
                } else if changes == nil {
                    Text("Any uncommitted changes are saved first, in Application Support › Volant › Worktree Backups.")
                }
            }.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { model.cancelWorktreeRemoval() }.disabled(model.worktreeBusy)
                Spacer()
                Button(role: .destructive) { model.confirmWorktreeRemoval() } label: {
                    Text(model.worktreeBusy ? "Removing…" : "Remove Worktree")
                }.disabled(model.worktreeBusy)
            }
            Spacer(minLength: 0)
        }.padding(24)
        .onExitCommand { model.cancelWorktreeRemoval() }
    }
}
