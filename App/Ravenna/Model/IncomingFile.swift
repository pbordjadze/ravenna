import Foundation
import os

/// An image another app handed over through "Open in Paint by Moonlight" (share sheet, Files).
nonisolated struct IncomingImage: Sendable, Equatable {
    /// The file's bytes; empty when it couldn't be read, which the create flow reports as a
    /// photo that couldn't be opened, like any other undecodable file.
    var data: Data
    /// The painting's title: the file's name without its extension, trimmed. Nil when that is
    /// empty, so the create flow falls back to the date like any other photo.
    var title: String?
}

/// Reads files the system opens in the app. The app declares image document types without
/// opening in place (`Config/Info.plist`), so the system copies each file into
/// `Documents/Inbox`, where it stays until the app deletes it.
nonisolated enum IncomingFile {
    /// Where the system puts files opened in the app.
    static var inbox: URL { URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory) }

    /// Reads the file and, once it has been read (or couldn't be), deletes it if it is the
    /// app's own inbox copy. Files from elsewhere are the owner's: the scoped access Files
    /// grants is released again and the file stays.
    @concurrent
    static func take(_ url: URL, inbox: URL = IncomingFile.inbox) async -> IncomingImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.create.error("Reading an opened file failed: \(String(describing: error), privacy: .private)")
            data = Data()
        }
        removeIfInInbox(url, inbox: inbox)
        return IncomingImage(data: data, title: title(for: url))
    }

    /// Deletes a file that won't be opened (the others of several opened at once).
    @concurrent
    static func discard(_ url: URL, inbox: URL = IncomingFile.inbox) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        removeIfInInbox(url, inbox: inbox)
    }

    /// The file's name without extension, trimmed; nil when nothing is left.
    static func title(for url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Whether `url` names something inside `inbox` (not the inbox itself). Both sides are
    /// resolved first: the system hands out `/private/var/...` paths for the container that
    /// `Documents` spells `/var/...`, and a link inside the inbox must not lead a delete out of it.
    static func isInInbox(_ url: URL, inbox: URL) -> Bool {
        let folder = inbox.resolvingSymlinksInPath().pathComponents
        let file = url.resolvingSymlinksInPath().pathComponents
        return file.count > folder.count && file.starts(with: folder)
    }

    private static func removeIfInInbox(_ url: URL, inbox: URL) {
        guard isInInbox(url, inbox: inbox) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.create.error("Deleting an inbox copy failed: \(String(describing: error), privacy: .private)")
        }
    }
}
