import Foundation

nonisolated enum AeroProjectMigrationError: Error, Equatable {
    case unreadableManifest
    case unsupportedPastVersion(Int)
    case unsupportedFutureVersion(Int)
    case incompatibleReaderVersion(Int)
}

nonisolated enum AeroProjectMigrator {
    static func decodeAndMigrate(_ data: Data) throws -> AeroProjectManifest {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["schemaVersion"] as? Int
        else {
            throw AeroProjectMigrationError.unreadableManifest
        }

        guard version <= AeroProjectSchema.currentVersion else {
            throw AeroProjectMigrationError.unsupportedFutureVersion(version)
        }
        guard version >= 0 else {
            throw AeroProjectMigrationError.unsupportedPastVersion(version)
        }

        var migrated = object
        var migratedVersion = version
        if migratedVersion == 0 {
            migrated["schemaVersion"] = 1
            migratedVersion = 1
        }
        if migratedVersion == 1 {
            if var composition = migrated["mediaComposition"] as? [String: Any],
               var overlays = composition["timedOverlays"] as? [[String: Any]] {
                for index in overlays.indices {
                    overlays[index]["bounds"] = ["x": 0.1, "y": 0.1, "width": 0.35, "height": 0.15]
                    overlays[index]["colorRGBA"] = [1, 0.75, 0.1, 1]
                }
                composition["timedOverlays"] = overlays
                migrated["mediaComposition"] = composition
            }
            migrated["schemaVersion"] = 2
        }

        do {
            let migratedData = try JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys])
            let manifest = try makeDecoder().decode(AeroProjectManifest.self, from: migratedData)
            guard manifest.compatibility.minimumReaderVersion <= AeroProjectSchema.currentVersion else {
                throw AeroProjectMigrationError.incompatibleReaderVersion(
                    manifest.compatibility.minimumReaderVersion
                )
            }
            return manifest
        } catch let error as AeroProjectMigrationError {
            throw error
        } catch {
            throw AeroProjectMigrationError.unreadableManifest
        }
    }

    static func encode(_ manifest: AeroProjectManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
