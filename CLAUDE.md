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
- `assets/audio/enemies/enemy_troop_1_firing.mp3` - the grunts' green cannon
  firing sound, supplied by the owner (sha256
  f038d06ab59e72fa940758b92f99fa0b9104e0e885bc3c80c0e69b0adba46614). `RobotEnemy` plays it via `Sfx.ENEMY_TROOP_1_FIRING`.
- `assets/audio/enemies/machine_death.wav` - played as the robot boss starts
  to die, supplied by the owner (sha256
  87429e38c8a4d01b44147f426b68fd629685e4e7ebd7cffc06d50613d84902b2). `RobotBoss.die()` plays it via `Sfx.MACHINE_DEATH`.

- `assets/audio/enemies/small_robot_death.mp3` - grunts killed by weapon fire
  (not when they break apart: black holes, explosions), supplied by the owner
  (sha256 ea1e3439974adfbb32416bff3afc2b551b9ea5f45ab8a71ccc1dcabaf6a8683b).
  `RobotEnemy.die()` plays it via `Sfx.SMALL_ROBOT_DEATH`.
- `assets/audio/enemies/mini_boss_machine_gun_firing.mp3` - the robot boss's
  chaingun, supplied by the owner (sha256
  8a8a3c992550305ef893b8ccd1b67ab3f9920c118f17e2776ba5728b9d20c978). A recording of
  continuous fire: `RobotBoss` plays one shot cut from it per round fired
  (`chaingun_shot_starts`), so it matches the real rate of fire.
- `assets/audio/enemies/mini_boss_missile_firing.mp3` - the robot boss's
  missile launch, supplied by the owner (sha256
  5e7a586a472f453020cf2148a1fdd17f37be59de52b3e981e5d46ea41229b7c7).
  `RobotBoss.fire_missile()` plays it from the blast's onset
  (`missile_sound_start` 1.03 s) so it is in sync with the launch.

## Owner's current choices (don't undo without asking)
- Skirmisher yellow barrel-end glow is off (`barrel_glows_enabled = false`);
  their muzzle flashes stay on. The player's machine gun effects (barrel heat
  glow, overheating, etc.) are separate and stay as they are.

## Approved save points
- Branch `saved/approved-2026-10-09` (commit 730b224): the owner said
  everything is good. It's the known-good state to compare against or roll
  back to. Never push to, move or delete `saved/*` branches.

## Shipping a change
- Test: `godot --headless --fixed-fps 60 --path . -s tests/movement_smoke_test.gd`
  (~1 min; must end `FAILURES: 0`).
- Commit and push to the working branch; `.github/workflows/web-build.yml`
  tests, exports and deploys (~3 min to live).
- When a build is live, always give the owner the link:
  https://harb666.github.io/CONSTRUCT-ERROR_V1/ (and a `?v=<anything>`
  variant to skip the phone's cache), plus the build label to look for.
