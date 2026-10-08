# CONSTRUCT-ERROR - working rules (from the game's owner)

## Nothing changes without telling the owner
- Only change what the owner asked for. Anything else that would change how
  the game looks, sounds or plays (even a side effect of a fix) must be named
  to the owner first, plainly, before or in the same message as the change.
- Never "tidy up", retune or replace existing gameplay, visuals, audio or
  settings on your own initiative.

## Protected - never replace, regenerate or edit without asking
- `assets/audio/plasma/pistol_cannon_firing.ogg` - the player's pistol cannon
  firing sound, supplied by the owner (sha256
  d7ac2450dd3b41bc5c791471bc3ad987f4ff0b8af60659fee657a41f50b7e371; a test
  fails if it changes). `PlasmaCannon` plays it via `Sfx.PISTOL_CANNON`.
- `assets/audio/plasma/shotgun_firing.mp3` - the player's shotgun firing
  sound, supplied by the owner (sha256
  66d93f1c970fcf61603d3489d508947f3d83268ab539f1eadf61e58fad6712db; a test fails if it
  changes). `Shotgun` plays it via `Sfx.SHOTGUN_FIRING`.

## Shipping a change
- Test: `godot --headless --fixed-fps 60 --path . -s tests/movement_smoke_test.gd`
  (~1 min; must end `FAILURES: 0`).
- Commit and push to the working branch; `.github/workflows/web-build.yml`
  tests, exports and deploys (~3 min to live).
- When a build is live, always give the owner the link:
  https://harb666.github.io/CONSTRUCT-ERROR_V1/ (and a `?v=<anything>`
  variant to skip the phone's cache), plus the build label to look for.
