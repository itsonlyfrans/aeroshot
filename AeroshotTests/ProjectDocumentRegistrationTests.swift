import Foundation
import Testing

struct ProjectDocumentRegistrationTests {
    @Test func bundleRegistersAndRoutesAeroshotProjectPackages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistData = try Data(contentsOf: root.appending(path: "Aeroshot/Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let declarations = try #require(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let documents = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(declarations.contains { $0["UTTypeIdentifier"] as? String == "com.aeroshot.project" })
        #expect(documents.contains {
            ($0["LSItemContentTypes"] as? [String])?.contains("com.aeroshot.project") == true
        })

        let source = try String(contentsOf: root.appending(path: "Aeroshot/App/AppDelegate.swift"))
        #expect(source.contains("url.isFileURL, url.pathExtension.lowercased() == \"aeroshot\""))
        #expect(source.contains("openProjectForUser(at: url)"))
    }
}
