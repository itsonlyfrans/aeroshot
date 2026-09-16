# Aeroshot

Aeroshot is an open-source macOS screenshot and screen recording app built in Swift.

It is designed as a fast, native capture tool that can grow from simple screenshots and recordings into a more complete capture and editing workflow.

> **Status:** Aeroshot is under active development. Some features and workflows may still change before a stable release.

## Features

Aeroshot currently includes or is actively developing:

- Screenshot capture
- Screen recording
- Microphone audio recording
- Webcam overlays during recordings
- Capture and recording recovery workflows
- Scrolling capture and image stitching
- Screenshot editing and annotation tools
- Video and media editing workflows
- GIF tooling
- OCR / text recognition
- Capture history
- Configurable hotkeys
- Export workflows
- macOS automation support
- Native `.aeroshot` project files

## Why Aeroshot?

The goal is to keep capture fast while making the result highly editable. Rather than treating a recording as one fixed output, Aeroshot is being built around workflows where capture, audio, webcam, cursor behavior, effects, and editing can remain flexible after recording.

## Development

Aeroshot is a native macOS project built with Swift and Xcode.

### Requirements

- macOS
- Xcode
- Xcode Command Line Tools

### Build locally

```bash
git clone https://github.com/itsonlyfrans/aeroshot.git
cd aeroshot
open Aeroshot.xcodeproj
```

Select the Aeroshot scheme in Xcode and run the app.

Because Aeroshot captures the screen and can use microphone and camera input, macOS may request the corresponding permissions when those features are used.

## Project structure

The repository is organized around focused parts of the capture workflow, including capture, editing, export, media studio, GIF tools, OCR, history, automation, hotkeys, diagnostics, and tests.

## Contributing

Contributions, bug reports, and ideas are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the basic development and contribution workflow.

If you find a bug, please open a GitHub issue with the macOS version, what you were doing, what you expected to happen, and what happened instead.

## Open source

Aeroshot is open source under the [MIT License](LICENSE).

## Maintainer

Aeroshot is currently maintained by [@itsonlyfrans](https://github.com/itsonlyfrans).
