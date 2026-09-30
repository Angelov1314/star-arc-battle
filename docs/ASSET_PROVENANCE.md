# Asset provenance

This snapshot keeps only the assets referenced by the current 0.5.2 project.

## Generated art

The PNG files under `assets/art/` were generated for this project with the built-in image generation tool. The corresponding prompt files and dimensions are recorded in `assets/art/manifest.json`. The manifest deliberately says that the generated images have not received an independent legal review; public visibility is not a legal clearance.

## Procedural audio

The WAV files under `assets/sound/original/` are deterministic offline synthesis outputs. `assets/sound/original/README.md`, `manifest.json`, and `tools/generate_original_audio.py` describe the generator and state that no samples, MP3s, or third-party source audio were used.

## Removed material

The old prototype MP3 directory, generated UI leftovers, Godot import metadata, build archives, editor caches, local logs, and user save data are excluded from this snapshot. No external service credentials or account configuration are required by the project.

## Reuse boundary

There is no blanket open-source license for the project. Keep this provenance file and the adjacent manifests if the author separately authorizes reuse of any individual asset.
