# Website claim map

This file maps public feature statements to current product code and automated evidence. Website-only demonstrations are labelled as concepts or illustrations.

| Public statement | Shipping surface | Automated evidence |
|---|---|---|
| Capture screenshots, videos, and GIFs. | `CaptureController`, `RecordingController`, `ScreenRecordingService`, `GIFRecordingService` | `RecordingControllerIntegrationTests`, `GIFStudioTests` |
| Add annotations. | `EditorDocument`, `EditorWindowController`, `AnnotationRenderer` | `AnnotationEngineTests`, `AnnotatorHonestyTests` |
| Extract text with on-device OCR. | `OCRCaptureController`, `OCRService` | `AeroshotTests` OCR and PII suites |
| ShareSafe scans and redacts sensitive image regions locally. | `ShareSafeService` | `PIIDetectorTests`, signed Share Safe UI test |
| Record MP4 or GIF with click highlights and timed callouts. | `RecordingController`, `RecordingEffectEventRecorder`, Video and GIF Studio | `RecordingSessionTests`, `VideoStudioModelTests`, `GIFStudioModelTests` |
| History stores captures and searches names, manual tags, and recognised text. | `HistoryStore`, `CaptureTrayView` | `ProjectLibraryTests` |
| Scrolling capture stitches captured segments. | `ScrollingCaptureController`, `ImageStitcher` | `ImageStitcherTests` in `AeroshotTests` |
| Screenshots save to `Pictures/Aeroshot` by default. Clipboard copy and automation are configurable. | `SettingsStore`, Settings Atlas | `SettingsStoreTests`, `SettingsAtlasTests` |
| Aeroshot requires macOS 14.6 or newer. | Xcode deployment target, `docs/BUILDING.md` | `ReleaseScriptSafetyTests` website truth check |
| Public signed downloads are not available. | Website FAQ and security page, `docs/DISTRIBUTION.md` | `ReleaseScriptSafetyTests` website truth check |

The website timeline is an illustration. OCR macros are a concept. Neither surface is presented as current app behavior.
