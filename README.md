# CONSTRUCT-ERROR

Third-person mobile co-op arena shooter (Godot 4.7, GL Compatibility renderer).
Current state: **movement prototype only**.

## Play the latest build
https://harb666.github.io/CONSTRUCT-ERROR_V1/  (rotate phone to landscape)

Every push to `main` or `claude/**` runs `.github/workflows/web-build.yml`:
import → headless movement smoke test → Web export → publish to the `gh-pages` branch.
The HUD shows the branch/commit of the running build.

## Controls
| Touch | Keyboard / pad |
|---|---|
| Left side: floating move stick | WASD / left stick |
| Right side: drag to look | mouse drag / right stick |
| JUMP (tap again in air = double jump) | Space / A |
| DODGE (direction = stick, else facing) | Q or Ctrl / B |
| SPRINT (toggle; turns off when you let go of the stick) | Shift (hold) / RT |

## Layout
- `scripts/input/` – `PlayerCommand` (one tick of intent, serialisable), `PlayerInput` (source base class), `LocalPlayerInput` (this device).
- `scripts/player/player_controller.gd` – movement; reads only its `PlayerInput`, no globals. `simulate(cmd, dt)` is the single tick step.
- `scripts/camera/camera_rig.gd` – per-local-player orbit camera; owns view yaw used for camera-relative movement.
- `scripts/ui/touch_controls.gd` – multi-touch stick / look / buttons.
- `scripts/character/character_animator.gd` – builds the AnimationTree state machine and drives it from the controller (visual only, no root motion).
- `scripts/character/arm_aim_modifier.gd` – procedural upper-body layer: raises both arms so the forearm cannons point forward while running/sprinting (re-poses only the existing UpperArm/ForeArm bones at runtime).
- `scripts/character/hips_corrector.gd` – runtime-only Hips pose fix-up that keeps clips with baked travel/turning in place.
- `assets/characters/grinch/grinch.glb` – source character (28-joint Mixamo rig; never modified). Textures are extracted next to it and imported at 1024 px.
- `scripts/main.gd` – `spawn_player(id, is_local)`; the future network layer plugs in here.
- `tests/movement_smoke_test.gd` – `godot --headless --path . -s tests/movement_smoke_test.gd`

## Character animation mapping
| State | Clip | When |
|---|---|---|
| Locomotion | Idle 9 → Walking → Running → RunFast | 1D blend on horizontal speed, playback rate scaled with speed |
| Jump / AirJump | Regular Jump (take-off → air segment) | jump / double jump |
| Fall | Fall2 (loop) | descending |
| LongFall | Fall1 (loop, lifted to capsule centre) | falling > 1.1 s |
| Land | Regular Jump (landing segment) | hard landing while not running |
| Dodge | slide right (slide segment, in place) | dodge in any direction |
| TurnLeft / TurnRight | Idle Turn Left / Right (in place, yaw from gameplay) | turning on the spot |
| SharpTurnRight | Run Sharp Turn Right (plant segment) | fast right turn while running |
| Dead | Dead | `CharacterAnimator.play_death()` (no death gameplay yet) |
| Climb | Climb Attempt and Fall 5 | defined, not triggered yet |

## Props
- `scenes/props/weapon_spawn_pad.tscn` – **drop-in prefab**: purple weapon spawn pad + matching walk-on ramp + collision + additive purple glow sprites (flat ring glow + camera-facing halo; procedural gradients, no lights). Instance it anywhere (it sits on y = 0 of wherever you place it).
  - `assets/props/weapon_spawn_pad/weapon_spawn_pad.glb` – optimized pad model (8.5 MB).
  - `pad_ramp_mesh.res`, `pad_ramp_shape.res`, `pad_ramp_material.tres` – pad sunk 0.15 m into the floor; ramp lip (tucked under the pad rim → r 1.07 m, 0.15 m rise), textured with the atlas patch that best matches the pad's outer wall colour; auto-LODs disabled on the pad. Regenerate with `godot --headless --path . -s tools/build_pad_ramp.gd`.

## Weapons (pickup/spawn system)
- `WeaponDefinition` (`scripts/weapons/weapon_definition.gd`, instances in `resources/weapons/`) – data for one weapon: scene, mount bone/side/offset, pickup display height. New weapons = new definition + weapon scene; no new pickup code.
- `Weapon` (`scripts/weapons/weapon.gd`) – base for weapon scenes; finds standard markers (`Arm_Socket_Attachment`, `Muzzle_Exit`).
- `WeaponSpawnPad` (pad prefab root) – set its `weapon` to any definition on each placed pad; its `WeaponSpawner` child floats, spins and bobs the weapon and hands it to the first player with a `WeaponHolder` entering the zone (`respawn_time` optional).
- `WeaponHolder` (on the player) – equips onto an existing bone via `BoneAttachment3D`; keeps the socket on the forearm axis and the weapon upright each frame. While armed, that arm is held raised by the existing arm-aim layer.
- Black Hole Generator: `scenes/weapons/black_hole_generator.tscn` (gun GLB, optimized 28 MB → 10 MB) spawns `scenes/weapons/black_hole_core.tscn` (separate, unmodified animated black-hole GLB, normalized to 1 m) at the gun's `Black_Hole_Projectile_Spawn` marker. `detach_core()` is there for firing later.
