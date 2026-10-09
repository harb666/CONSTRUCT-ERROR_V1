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
- `assets/audio/enemies/small_robot_death_2.mp3` (sha256
  068c10ac9adb8704966c38943368516f79b79a4ff27f7c341f9c500a6a834b8b) and
  `assets/audio/enemies/small_robot_death_3.mp3` (sha256
  016f968e811eb248e42a2bdeed35ab97b73fce134bfa143355c08b56dece5676) - the
  owner's other two grunt death sounds. Each such death plays one of the
  three at random (never the same twice running); `_2` starts 0.15 s in
  (it opens with 0.2 s of silence).
- `assets/audio/enemies/skirmisher_death_1.mp3` (sha256
  fc3851afdc35059268d9f56767a08cc1b541c60ebba3cc436682ed4f9c6d8eaa) and
  `assets/audio/enemies/skirmisher_death_2.mp3` (sha256
  7ca7ef836bf83eff88afdb56b8ec51517600ae7d3b4f6234400d7951c6f11732) - the
  owner's skirmisher death sounds. Every skirmisher death plays one of the
  two at random (`RobotSkirmisher._death_sound()`); `_1` starts 0.3 s in
  (`skirmisher_death_1_start`, past its faint build-up).
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
- Skirmishers are twice as big (`RobotSkirmisher.size_scale = 2.0`): model,
  hitbox, target point, steps, jump and dive lunge scale; speeds, health and
  weapons don't.
- Skirmisher movement / lower body is approved as of 536f448 - don't change
  it: RobotWalker legs, the clip locked to the steps (CLIP_MID_LEFT),
  cadence 0.9-2.1, turn stepping, snap_turn_rate, jump/dive hand-backs.
- Dead skirmishers settle onto the floor after their death clip
  (`_settle_corpse`: the posed body tips over as one rigid shape); the clips,
  rig and skeleton are not changed for this.
- Skirmisher break-off pieces collide with their own outline
  (`BreakApart.hull_shapes`, skirmisher only), so a detached arm falls clear
  and lies on the floor. Grunts / boss keep their box shapes.

## Approved save points
- Branch `saved/approved-skirmisher-movement` (commit 536f448): the owner
  approved the skirmisher movement.
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
