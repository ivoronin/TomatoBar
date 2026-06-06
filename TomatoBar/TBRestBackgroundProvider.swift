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

    func randomImage(folderPath: String) -> NSImage? {
        guard !folderPath.isEmpty else { return nil }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
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
