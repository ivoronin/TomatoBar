import AppKit
import Foundation

struct TBRestBackgroundProvider {
    private let fileManager: FileManager
    private let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp"
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func randomImage(folderPath: String, bookmarkData: Data) -> NSImage? {
        if let image = randomImage(bookmarkData: bookmarkData) {
            return image
        }

        guard !folderPath.isEmpty else { return nil }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        return randomImage(folderURL: folderURL)
    }

    private func randomImage(bookmarkData: Data) -> NSImage? {
        guard !bookmarkData.isEmpty else { return nil }

        var isStale = false
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else {
            return nil
        }

        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        return randomImage(folderURL: folderURL)
    }

    private func randomImage(folderURL: URL) -> NSImage? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let imageURLs = contents.filter { url in
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return false
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }

        guard let selectedURL = imageURLs.randomElement() else { return nil }
        return NSImage(contentsOf: selectedURL)
    }
}
