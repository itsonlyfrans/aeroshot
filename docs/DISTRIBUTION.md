# Distribution

Aeroshot is paid, signed software with source available for inspection and
contribution. Source availability does not itself grant redistribution rights;
the repository license is authoritative. The portable `.aeroshot` format and
core capture/edit/export operations must not depend on license servers,
telemetry, or update infrastructure.

## Release path

1. Run unit and UI validation from `BUILDING.md`.
2. Run `scripts/build-release.sh` and review its dry-run commands.
3. Run it with `--execute` to create a local archive. This does not export it.
4. Export with an approved, locally maintained ExportOptions plist and a
   Developer ID Application identity from Keychain. Never commit either secrets
   or generated credential material.
5. Verify the exported `.app` with `scripts/verify-release.sh /path/Aeroshot.app`.
6. Submit the ZIP or DMG with `xcrun notarytool submit ... --keychain-profile
   "$AEROSHOT_NOTARY_PROFILE" --wait`, staple it, and re-run verification with
   `AEROSHOT_REQUIRE_NOTARIZATION=1`.
7. Perform a clean-machine smoke test before publishing or updating any feed.

Signing, notarization, update-feed mutation, and publication are human release
actions requiring credentials. The repository scripts do not create identities,
store secrets, upload artifacts, or publish releases.
