# Original Audio Assets

All WAV files in this directory are original procedural synthesis, rendered offline at 22,050 Hz, 16-bit PCM. They use no samples, MP3s, or third-party source audio.

Run `python3 tools/generate_original_audio.py` from the project root to regenerate every file and `manifest.json` deterministically. The manifest records final rendered durations, frequency/noise/chord parameters, and the music structure.

For listening, play `original_sfx_audition.wav` first; it presents SFX in the manifest order with 120 ms gaps. Then listen to `music/town_loop.wav` and `music/battle_loop.wav`; each is a 36-second loop with a zero-sample PCM loop boundary.
