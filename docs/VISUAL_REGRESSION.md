# Visual regression checks

The signed UI suite compares screenshots only when an approved baseline set is available. It does not create or replace baselines.

Set `AEROSHOT_VISUAL_BASELINE_DIR` to a reviewed directory. The directory must contain `manifest.json` and every image named by the manifest. The manifest uses this form:

```json
{
  "schemaVersion": 1,
  "approved": true,
  "maxChannelDelta": 8,
  "maxDifferingPixelRatio": 0.001,
  "fixtures": {
    "settings-light": {
      "file": "settings-light.png",
      "masks": []
    }
  }
}
```

Mask coordinates use top-left pixel coordinates. Each mask needs integer `x`, `y`, `width`, and `height` values. Use a mask only for an approved dynamic region.

Run `scripts/run-ui-tests.sh` on the same macOS version, display scale, color profile, and window size used for approval. The suite fails on a missing fixture, a size change, an unreadable image, an invalid tolerance, or a pixel ratio above the manifest limit. It skips visual rows when no approved baseline directory is set, so screenshot existence never reports a pass.

Baseline changes require human review of the old image, new image, and diff. Set `approved` to `true` only after that review. Keep hardware, macOS, scale, color profile, and reviewer details with the reviewed baseline artifact.
