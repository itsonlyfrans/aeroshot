# Distribution

Aeroshot plans to use signed distribution with source available for inspection.
Pricing and license terms are not final. Do not publish a public build until
approved terms exist in the repository. The portable `.aeroshot` format and
core capture, edit, and export operations must not depend on license servers,
telemetry, or update infrastructure.

## Release path

1. Run unit and UI validation from `BUILDING.md`.
2. Run `scripts/build-release.sh` and review its dry-run commands.
3. Run it with `--execute` to create a local archive. This does not export it.
4. Export with an approved, locally maintained ExportOptions plist and a
   Developer ID Application identity from Keychain. Never commit either secrets
   or generated credential material.
5. Submit the ZIP or DMG with `xcrun notarytool submit ... --keychain-profile
   "$AEROSHOT_NOTARY_PROFILE" --wait`, then staple it.
6. Verify the stapled `.app` with `scripts/verify-release.sh /path/Aeroshot.app`.
   Use `AEROSHOT_REQUIRE_NOTARIZATION=0` only for a preflight inspection.
7. Perform a clean-machine smoke test before publishing or updating any feed.

Signing, notarization, update-feed mutation, and publication are human release
actions requiring credentials. The repository scripts do not create identities,
store secrets, upload artifacts, or publish releases.
