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

## Tap-to-target auto fire
Four separate, reusable pieces (any weapon/enemy can use them):
- `Targetable` (`scripts/targeting/targetable.gd`) – put on anything lockable, at its aim point. Forgiving tap area (`select_radius`, `select_half_height`), `kill()/revive()`, stable `target_id` for networking.
- `TargetSelector` (local player only) – turns a tap into a target: screen-space hit area around each enemy (at least `min_tap_radius` px), closest to the tap wins. Tap = lock, same again = unlock, other = switch.
- `TargetLock` (on every player) – holds the target sent in `PlayerCommand.target_id`; clears on death / invalid / beyond `max_range` (40 m) and emits `target_lost`.
- `WeaponHolder` auto-fire – while locked, fires whenever the weapon's barrel is within `fire_cone_degrees` of the target and `weapon.can_fire()`; each weapon sets its own rate/projectile via `fire_at()`.
- Upper body: `ArmAimModifier` twists the spine (±60°) and aims the armed arm at the target; hips/legs keep following movement. Standing still, the player turns to face the target.
- UI: lock-on ring (`scripts/ui/target_marker.gd`). The old FIRE button and crosshair are gone.
- Test dummies are enemies: 5 hits to destroy, respawn after 4 s.
- `BlackHoleGenerator.fire_at()` releases the chamber core as a `BlackHoleProjectile` (same node, animation keeps playing; disk turned to face back along the flight path). It flies straight, stops on the first hit (calls `on_projectile_hit` if the collider has it), collapses and frees. A new core grows in the chamber after `recharge_delay` (12 s) over `recharge_grow` (3 s): 15 s between shots.
- `BlackHoleProjectile.impacted` is the hook for gravity / damage / supernova later.
- Armed: camera eases to an over-the-shoulder offset.

## VFX (Black Hole Generator)
`scripts/vfx/` – visual only, no gameplay logic. Textures: 10 greyscale sprites from Kenney's Particle Pack (CC0, `assets/vfx/`, 52 KB total) tinted at runtime with additive unshaded materials; CPUParticles3D (WebGL-safe).
- `MuzzleFlash` – crossed flame quads along the barrel, star pop, brief purple light.
- `ChamberArcs` – flickering lightning strips between the contained core and the containment ring (only while charged). The chamber also has a small, subtle distortion disc (`chamber_lens_size`/`chamber_lens_strength` on the gun) that fades out before the chamber frame.
- `BlackHoleFlightVfx` – gravity distortion (`gravity_distortion.gdshader`, screen-texture lens/twist), event-horizon ring, counter-rotating swirls, matter spiralling in, crackles. `Vfx.distortion_enabled` turns the distortion off if a device struggles.
- `ImpactBurst` – flash, scorch star, expanding shock ring, sparks, light pop (also used as the expansion pulse).
- `BlackHoleLightning` – pooled procedural lightning (14 small + 4 large bolt meshes, jagged forking camera-facing ribbons) lashing outward; each strike casts one ray (biased down/sideways) and lands on real surfaces/enemies when in reach (more likely the nearer they are), with pooled flashes, sparks and one shared light.
- Fired projectile: stays chamber-sized until `clear_distance` (1.4 m), then surges (ease-out with overshoot + pulse) to `flight_size` 3 m. Collision is a sphere sweep with `collision_radius` = 22% of the diameter; `influence_radius` (1.2x diameter) is there for gravity later.

## Recoil (Black Hole Generator)
Sequence: `fire_at()` starts a 0.18 s charge (core swells/shudders, arcs frenzy, chamber lens surges) → launch → `Weapon.recoiled` → `WeaponHolder` kicks the `CharacterAnimator` recoil spring (fast kick, rebound, settle) and emits `weapon_recoil` (the camera no longer reacts; `CameraRig.kick()` still exists if wanted later).
- `ArmAimModifier` applies the spring additively: firing arm's elbow driven back + forearm/muzzle climb; chest (Spine2 only) leans back and twists. Hips/legs and movement untouched.
- `WeaponHolder._align_weapon` slides the weapon back along its barrel and pitches the muzzle up with the same spring.
- Gun mechanics: `Front_Muzzle_Deep_Bore` slams back and rebounds; `Finished_Containment_Interior` spins 120° per shot.

## Black hole impact → gravity well → supernova
`BlackHoleProjectile` states: FIRED → TRAVELLING → STUCK_GRAVITY_WELL → COLLAPSING → SUPERNOVA → FINISHED (flying full range without a hit just fizzles).
- On hitting anything it sticks at the contact point for `gravity_well_duration` (5 s), pulsing irregularly; instability ramps up suction, spin (core animation speed_scale), lightning violence, particles and distortion. At most `max_active_wells` (3) at once; the oldest collapses early.
- `GravityWell` (`scripts/weapons/gravity_well.gd`): one sphere query every 0.15 s on the **movable** physics layer (layer 2: props, enemies, players), nearest `max_affected_objects` kept. Clamped inward/orbital/total speeds, mass resistance (sqrt(mass/ref)), lift near the core, visual shrink/spin via the body's mesh children (original transforms stored; body scale never touched). Inside `capture_radius` bodies are captured: collision off, kinematic, tiny orbit in the core (max `max_captured_objects`).
- Players: `PlayerController.external_velocity` – the pull is added on top of normal movement (capped at 8 m/s; sprint escapes). Supernova shoves via `apply_external_impulse`.
- Collapse: rapid shrink to a pinpoint + brief bright compression, then `SupernovaBlast` (flash, two shock rings, distortion bubble, sparks, light) and `GravityWell.supernova()`: captured bodies released one per physics tick at spread, ray-checked positions with restored collision/size, ONE capped launch each (`max_launch_speed`), radial damage (`take_damage`), brief camera kick for nearby local players.
- Tunables on the projectile: gravity_well_duration, gravity_radius, gravity_strength, player_gravity_strength, capture_radius, orbit_strength, shrink_rate, pulse_amount, pulse_speed, supernova_radius, supernova_damage, supernova_launch_force, maximum_affected_objects, maximum_captured_objects, max_active_wells.
- Arena: dummies are now heavy upright RigidBody3D enemies; `Props/` has light crates, barrels and a heavy block (`PhysicsProp`).

## Black hole particles
While travelling (and while stuck) `BlackHoleFlightVfx` adds purple glow motes and black dust orbiting the disc (local space) and a dark purple mist (`assets/vfx/smoke_puff.png`, alpha-blended via `Vfx.mix_material`) shed into the world so it trails and tumbles behind.

## Black hole audio
All sounds are `DynamicSound`s (`scripts/audio/dynamic_sound.gd`, created via `Sfx` in `scripts/audio/sfx.gd`): panned in 3D, full volume within `near` metres of the local player (group `sfx_listener`), fading smoothly (squared) to silence at `far`. Godot's own attenuation is disabled so the curve is identical on web and desktop. Files in `assets/audio/black_hole/`:
- `fire.ogg` — the gun, on launch with the muzzle flash, from the muzzle (`fire_volume_db/near/far` on `BlackHoleGenerator`).
- `energy_loop.ogg` — hum attached to the black hole from the barrel until the supernova (fades on a fizzle).
- `charge.ogg` — rising charge while the black hole is stuck, timed to end `charge_end_gap` (0.05 s) before the supernova: it is longer than the well, so it starts part-way through.
- `energy_burst.ogg` — starts `burst_lead_time` (1.3 s) before the supernova; at the same instant thick blue-violet lightning erupts from the black hole (`BlackHoleLightning.erupt()`, `max_erupt`/`erupt_interval`/`erupt_reach`).
- `explode.ogg` — at the supernova; the loudest sound and audible furthest away.
Volumes/ranges are exports on `BlackHoleProjectile` (Audio group). After firing, `BarrelStatic` (scripts/vfx/barrel_static.gd) crackles arcs across the empty chamber and out of the muzzle with a plasma glow and sparks (starts `cooldown_static_delay` = 1 s after the shot, follows `COOLDOWN_ENVELOPE`).

## Robot enemy, damage and break-apart
- **Model**: `assets/characters/robot/robot_enemy.glb` (used as-is: rig, skin weights, clips and the 13 prepared body sections are untouched; only its textures are import-capped at 1024 for mobile). `scenes/enemies/robot_enemy.tscn` / `scripts/enemies/robot_enemy.gd` (`RobotEnemy`): heavy upright RigidBody3D (gravity wells pull/capture/throw it), walks a short patrol (`patrol_distance`, `patrol_axis`), `max_health`.
- **Damage**: `DamageInfo` (`scripts/combat/damage_info.gd`): `damage_amount`, `damage_type` (GENERIC/BULLET/ENERGY/IMPACT/EXPLOSION/SUPERNOVA), `impact_position`, `impact_direction`, `impact_force`, `explosive_force`. Deliver with `DamageInfo.apply(target, info)` (calls `apply_damage(info)`, falling back to `take_damage(amount, from)`). The black hole's direct hit sends ENERGY (`impact_damage` 1, `impact_force` 6); the supernova sends SUPERNOVA with `explosive_force = supernova_explosive_force (42) * distance falloff`.
- **Death**: at 0 health all behaviour stops and one of the GLB's own clips plays: ENERGY kills -> `Electrocuted_Fall`; otherwise by hit direction (`Shot_and_Fall_Backward` from the front, `Shot_in_the_Back_and_Fall` / `Shot_and_Fall_Forward` from behind). Corpses settle, freeze and stop processing; cleared after `corpse_time`, respawn after `respawn_time` (testing).
- **Break-apart** (`scripts/destruction/`, reusable): `BreakSection` resources (`resources/enemies/robot_break_sections.tres`) describe the section tree (meshes, driving bone, joint bone, size tier). `BreakApart.choose_level(info)` maps destructive power `(impact+explosive)/reference_force` (+ explosive bonus, +/- `randomness`) to NONE/LIGHT/MEDIUM/HEAVY/EXTREME (`level_thresholds`); `plan()` picks joints (impact-near parts favoured; LIGHT = 0-1 small part, MEDIUM 1-3, HEAVY 3-5 incl. major, EXTREME everything minus up to `extreme_keep`); breaks cascade shortly into the death (`break_delay`, `break_stagger`). Nothing is cut: a section's meshes move, still skinned, onto a frozen copy of the skeleton inside a `DebrisPiece`, keeping their exact pose.
- **Debris** (`DebrisPiece`): box collision per section (`shape_shrink`), mass from size, launch away from the blast steered by its direction (`base_launch_speed`, `launch_per_power`, `max_launch_speed`, `max_spin`), linear/angular speed clamped every tick, low bounce, ignores other fresh debris for `self_collision_delay`, own physics layer 3 "debris"; settled pieces freeze and stop processing; removed after `lifetime`; at most `DebrisPiece.max_active` (36) alive, oldest shrink away first.
- **Electrical failure**: `JointSparks` (pooled, 16): small spark burst, a few tiny purple/white arcs and a brief discharge at the broken joint on both the body and the piece, dying to occasional residual sparks; also subtle crackles on intact corpses and wounded robots.
- **Test arena**: 6 robots (2 HP) patrol in a cluster ahead of the spawn — a black hole among them gives a spread of extreme/heavy/medium/light results by distance; 3 lone robots (1 HP) far apart (left, right, far right) die to a direct black-hole hit with an ordinary, mostly intact electrocuted death.

## Supernova burst
`assets/vfx/supernova/supernova_finish.glb` is a 50-frame, 657k-vertex Sketchfab flipbook (layers pile up into an expanding plasma burst over 8.8 s). It is too heavy for the web build, so `tools/bake_supernova_finish.gd` bakes 9 of its layer groups (~124k vertices, 4 MB) into `supernova_finish_baked.scn` with each layer's original appear time; the GLB itself is excluded from export. `SupernovaFinish` (`scripts/vfx/supernova_finish.gd`) plays it at every supernova: layers appear in their original order compressed into `duration` 0.8 s (build-up, then fade), translucent (alpha blend, no depth writes), scaled to `supernova_radius + supernova_finish_margin` (1 m past the damage radius).

## Character mesh reduction
`grinch.glb` (110k -> 74k vertices) and `robot_enemy.glb` (108k -> 60k) were simplified with gltfpack (`-si 0.6` / `-si 0.2 -slb -kn -km -ke -ac -af 0 -noq`: named nodes/sections, materials, skins and the 28-bone rigs kept), then `tools/transplant_animations.py` copied the ORIGINAL animation data back in byte for byte (gltfpack thins keyframes), so every pose of every clip is identical to the source.
- **Living robots draw as one mesh**: `RobotEnemy` merges the 15 section meshes (same skin, same 2 materials, same skeleton) into one shared 2-surface mesh, built once on the first spawn (~30 ms desktop). Sections stay loaded but hidden; `die()` switches back to them before any breakup, so death/breakup behave exactly as before. 9 robots in view: 401 -> 86 draw calls; pixel output identical (max 1/255 rounding).
- **Distance and shadows**: beyond `far_distance` (30 m, 2 m hysteresis, Godot visibility ranges) a living robot draws `robot_enemy_far.glb` (9.5k vertices, made by `tools/make_robot_far.py`, textures stripped, reuses the main materials) instead of the 60k one; its shadow is always cast by that simple mesh (`ShadowProxy`, shadows-only) while the detailed body casts none. Removed on death with the merged mesh.
- **Stress test**: open the game with `?stress=30` (or `-- --stress=30`) to replace the arena robots with N patrolling robots and show frame time, draw calls, triangles, robots and memory in the HUD; `?perf=1` shows the numbers only.

## Robot combat
- **AI** (`RobotEnemy`, Combat group): finds the nearest player (group `players`) within `detect_range` (28 m, lost beyond 40 m), checks line of sight every 0.25 s (other robots don't block), fights from `preferred_range` 7–14 m: advances/backs off, strafes and switches sides every 1–2.4 s, flips away from walls, keeps apart from other robots, always faces the player (Walking/Running clips by speed). Helpless while a gravity well holds it. `RobotEnemy.ai_enabled` turns all robot AI off (tests).
- **Aiming**: `RobotArmAim` (SkeletonModifier3D) straightens the forearms and turns the shoulders so both cannon muzzles (green tips, `MUZZLES` in hand-bone space) point at the player, blended over the playing clip; it records the aimed muzzle positions for firing.
- **Firing**: bursts of 3–4 shots alternating left/right cannon (`burst_interval` 0.12 s), 1.3–2.3 s between bursts, 0.5–1 s reaction after spotting, slight lead and 2° spread, `fire_range` 26 m.
- **PlasmaBolt** (pooled 64): 30 m/s, one ray cast per tick (no physics body), flies through robots, damages via DamageInfo (players get `apply_damage` → hit count + green screen-edge flash; no health yet), nudges props.
- **PlasmaFx** (pooled): green muzzle flash + brief green light (max 4 lights shared), impact flash + ring + green sparks, and on level geometry a glowing green scorch mark that crackles with tiny arcs/sparks and fades in ~1.3 s.
