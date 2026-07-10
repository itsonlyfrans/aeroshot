# Security

Report vulnerabilities privately to the maintainer through the repository host's
private security-advisory feature. Do not open a public issue containing exploit
details, credentials, personal data, or captured media. Until that channel is
configured, withhold sensitive details and request a private contact channel in
a minimal issue.

Aeroshot processes high-sensitivity screen, camera, microphone, clipboard, and
filesystem data locally. Release credentials belong in the macOS Keychain or
ephemeral environment variables, never source control or scripts. Release
verification must inspect the exported artifact rather than assuming Xcode build
settings are the shipped signature or entitlements.
