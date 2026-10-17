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
- `assets/audio/enemies/mini_boss_walking.mp3` - the robot boss's footsteps,
  supplied by the owner (sha256
  d5dc01543c919ef0a022ff3fd73bd315f501919fee6069ae7c95163a1d37768e). Three
  heavy stomps, cut (owner allowed editing for sync) by
  `tools/cut_boss_steps.py` into `mini_boss_step_1/2/3.ogg`, each starting
  at its impact; `RobotBoss` plays one each time a foot lands in the clip
  (`STEP_TIMES`, `_update_steps`), so every step is heard, in sync.

- `assets/audio/weapons/rocket_launcher_firing.ogg` (sha256
  7e547e4c9ced3b9f03cc9db1ca55c946d38c39fcfb24c3f8c9ebfcd6289a8642) - the
  rocket launcher's firing sound, supplied by the owner. `RocketLauncher`
  plays it via `Sfx.ROCKET_FIRING`.
- `assets/audio/weapons/rocket_explode_0.ogg` (sha256
  9bfa4d9fc2c5e15978602a04463f513ebf55ccf342e20c7576dc0d730e7758a4),
  `rocket_explode_1.ogg` (sha256
  bf070f66400bc19faacb84a21c3a69a982062a13a44ece022155dd20b1f21752) and
  `rocket_explode_2.ogg` (sha256
  831c0268bb44ba7e415924f08b4eb1e6c11f9eda6b30ebb05128b0e63ea422f8) - the
  owner's rocket explosion sounds. Each rocket blast plays one at random,
  never the same twice running (`PlayerRocket._explode_sound`).

- `assets/audio/weapons/ice_blaster_firing.mp3` (sha256
  670952a74ae1d653cfc992ad18b538facca40f61e67330fac60f7bd4a4150bfc) - the
  Frost Byte's firing sound, supplied by the owner (`Sfx.ICE_BLASTER_FIRING`).
- `assets/audio/enemies/enemy_frozen_1.mp3` (sha256
  22fe39bf38c235dd9742d65a4591fae3a6c3af2255ffe308a386bb71593b16ba) and
  `assets/audio/enemies/enemy_frozen_2.mp3` (sha256
  15aee088d45669b72719954f02179a54ef1c4d58f900e58767ccc1c3f0875259) - the
  owner's frozen-enemy sounds: every frozen robot (boss too) plays them one
  after the other, never the same twice running, until it thaws or
  shatters (`FrostFreeze._next_sound`).

- `assets/audio/music/source/Main_menu_music.mp3` (sha256
  a1a935ad9d8b13c0c7021147ded1bf5972a8b3517d655f6fd96598bccd5fff37) and
  `assets/audio/music/source/Level_1_music.mp3` (sha256
  59bc99ce1d6e076dbad43441bfb103fc37f2ee3ae544d5775010f9d5b01dba2e) - the
  owner's music, kept untouched; the game plays 112 kbps OGG copies
  (the 320 kbps originals would add ~29 MB to the download).
- `assets/audio/music/source/Construct_error_menu_music_2.mp3` (sha256
  18ea48dadc8b2249c159aaa588b70f60cf52b8c949f4b8d9b86d807adba04405) - the
  owner's new main menu music (owner asked: it replaces the first one, whose
  original stays in `source/`, unused; its game copy was removed). The game
  plays `main_menu_music_2.ogg` (112 kbps). `Music`: menu music on the title
  (once loaded) and character select; Level 1's (`level_1_music.ogg`) as
  players arrive in a level, at -12 dB (owner asked for it louder, was -17;
  still under the weapons; menu -9), carrying on down the lift.

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
  and lies on the floor. Grunts / boss keep their box shapes. They (and the
  settling corpse) pass through robots' and players' capsules
  (`_ignore_characters`), so they can't be left resting on one in mid-air.
- Dying skirmishers keep their arms tucked in (owner chose this): during
  deaths only, each upper arm is held to at most `death_arm_raise_max` (50
  deg) from hanging down (`_limit_arms`, applied to the pose right after
  the clip each frame); the human death clips otherwise fling the arms out
  and the thin upper-arm rod makes the cannon look detached.
- Every skirmisher death breaks the right arm off at the shoulder as its own
  piece, which falls to the floor (`_schedule_arm_break` / `_break_now`;
  owner asked for this). The left arm only breaks off from strong hits, as
  before.
- Living skirmishers draw their joint caps (the "Interior" surfaces sealing
  each section's open edge at shoulders, hips, neck, waist;
  `_whole_mesh_skips` returns false), so a bent joint can't be seen through.
  Mesh, rig and animations unchanged.
- Skirmishers never jump (`jumps_enabled = false`; owner will design a new
  jumping character). Their evades are sidesteps and dives; the jump code
  is kept, unused.
- Rocket Launcher (owner's model, red pad): mounted / dual-wielded like the
  other arm weapons. Fires the rocket loaded in its bore (same size / look:
  the model's own warhead + a matching body) every 2.5 s, with a big muzzle
  flash, lots of smoke and heavy recoil (owner's spec). Its sounds are the
  owner's (below). Robots it hits or lands right next to (not the boss) die
  at once and are blown apart; it's kept weaker than the black hole gun
  (owner asked): splash doesn't kill, the boss takes 0.4 per rocket.

- Front end (owner asked): TAP TO START title (the tap turns sound on; the
  arena prepares behind it, meant to end the iPhone start-up silence) ->
  character select (roster: Grinch and Harbinger; cards use the owner's
  banner art in the cyan theme, HUD portrait = the face from that art;
  4-player co-op squad shown with open slots until online play exists) ->
  DEPLOY. HUD in the owner's cyan reference style, Ratchet: Gladiator
  layout (player panel top-left, arm weapons top-right).
- Glitchy main menu (owner asked; ideas from the owner's `glitch-video`
  repo, branch `glitch-music-video`): locked to the menu music's beat (133
  BPM, first beat 0.428 s - measured from the new track; own clock when the
  sound isn't moving), a 16-bar
  cycle of clean bars and bars where everything - the arena behind, panels,
  buttons, cards - merges into neon vector lines (edge pass in each
  source's hue, ragged blocky dissolve front with a glow, band shifts,
  drop-outs, RGB split, magenta / green ghosts; `MenuGlitch`,
  `menu_glitch.gdshader`), and the character preview dissolves into its
  real wire mesh (crease edges, skinned; `WireMesh`, `wire_line` /
  `wire_hide` shaders - one view: this renderer poses a skinned mesh per
  view). All menu text is drawn crisp on top (`HudStyle.defer_for`),
  outlined while lines show, so the menus stay readable.
- Lock-on reticles in the owner's sci-fi HUD reference style (owner asked):
  lock-in snap animation, segmented / tick rings, notches, brackets and a
  readout (arm, distance, target health); arm colours unchanged.

- Harbinger (owner's model) plays exactly like the Grinch (same player
  scene, only her visual swapped). Her arm-end blasters are cut off at the
  end of the blue gauntlets so weapons plug in like the Grinch's; her foot
  angle is corrected in her clips so her soles sit flat; her clips play a
  little slower (longer legs) so her feet don't slide. Her halo is a
  glowing blue electric ring (owner asked; shader-only, light on memory).

- Cartoon VFX (owner asked, from the GDQuest VFX repo review): puffy 3D
  fireballs/smoke for rocket + boss missile explosions and the rocket
  launcher's smoke; cartoon muzzle flashes (plasma cannon, shotgun, machine
  gun - player only, robots keep theirs) and cartoon shotgun beams;
  hologram teleport-in for players, respawning robots, pad weapons and the
  character-select preview; faint hologram coat on pad weapons.
- Shotgun in the Magma Cannon style (owner asked, Ratchet: Gladiator
  reference): fat flame jets with jagged fire bolts, a fan of fire tongues
  in the muzzle blast, fire bursts on impact. Hits are cartoon (owner
  asked): enemies and players flinch (snap back, squash and wobble), flash
  white-hot then the hit colour, and show a POW star; the player also gets
  a red screen-edge flash, but no camera shake on hits (owner asked).
  The boss doesn't squash.
  Streams leave a molten splat on walls / floor that cools to a scorch
  (`MagmaSplat`; owner asked), and every shot throws fiery blast rings out
  of the barrels, one lingering round the trails' start (`ShotgunBlastRing`;
  owner asked).
- Brighter, more dramatic muzzle flashes (owner asked): a VFEZ-style cartoon
  cel flash (`CelFlash`) layered OVER the existing flashes (unchanged) of
  the plasma cannon, machine gun, rocket launcher, the boss's chaingun
  (large, every round) and the black hole gun (big, purple / pink); grunts
  (green) and skirmishers (yellow) get smaller ones. Shotgun unchanged.

- Black hole portal (owner asked, owner's Purple_Portal video): an animated
  portal around every black hole (`BlackHolePortal`, child of the core,
  ring 1.7 x its size) that opens / collapses frame by frame exactly with
  the black hole's size (chamber growth, collapse, fizzle). The gravity
  lens disc is cut from 2.3 to 1.7 x (its outer layers were the big striped
  disc). Everything else on the black hole is unchanged.

- Melee punch-shot (owner asked): MELEE button (F / pad X), dimmed with
  nothing in reach (4.6 m). Right arm switches to the pistol cannon, right
  foot steps back, coil, lunge, straight cannon punch that fires as it lands
  (0.2 s), short hit-stop; grunts blown to pieces sent far, skirmishers 0.9
  damage + knocked back stumbling, never the boss. Camera swings round a
  little and back by 0.62 s (impact zoom, no shake). The right arm then goes
  back to its previous weapon. `PlayerMelee`, `MeleePoseModifier`.

- Boss foot stomp (owner asked): a player within 5.5 m gets stomped (4 s
  cooldown): knee up, foot slammed down, a mini toon shockwave (7.5 m) and
  the owner's stomp sound louder; players it reaches (not jumping it) take
  10 HP, are knocked way back, land on their backs and quickly kip up.
  `BossStompPose`, `StompShockwave`, `PlayerKnockdown`,
  `KnockdownPoseModifier`.

- Frost Byte (owner's model, white pad; owner asked): mounted / dual-wielded
  like the other arm weapons. Every 10 s (only with a locked target within
  17 m) it fires a blizzard of swirling white / ice-blue spirals, 16 m long,
  widening to ~5 m (`FrostBlizzard`), that freezes robots it reaches for
  20 s (`FrostFreeze`; owner asked, was 10): grunts / skirmishers become ice
  sculptures of their pose, the boss gets a frost layer and icicles. Any
  player hit on a frozen grunt / skirmisher shatters it into pieces that
  melt away; robots' fire doesn't. Shot while frozen, the boss is only
  slightly hurt (half damage) and thaws sooner (owner asked). Sounds are
  the owner's (below): ice blaster firing (+6 dB, owner asked for it way
  louder); frozen robots play the two frozen sounds one after the other
  while frozen, quiet unless the player is near (full within 2.5 m, silent
  at 9 m; boss 5-15 m). Its textures are stored like the other weapons'
  (1024, GPU-compressed; they were 2048 raw, ~64 MB of graphics memory).

- Heavy weapons (owner asked): the Black Hole Generator and the Frost Byte
  (`WeaponDefinition.heavy`) - right arm only, so never two at once; only
  light weapons dual-wield. Asked for on the left arm they go on the right.
  Wheel: gold HEAVY frame / plate, ghosted in the left half with an arrow
  across to the right arm; heavier lock-in (bigger burst, arm dips under
  the weight); HUD HEAVY plate.

- Skyforge Arena (owner asked) is the first part of the first level (the
  game now starts in the Toxic Works, owner asked; `?level=skyforge` for
  Skyforge): image-to-level's game-ready package, 4 grunts + 2
  skirmishers (no respawn), no weapon pads, player on the south tower deck.
  It must look exactly like the map maker (owner asked): its materials use
  `preview_lit.gdshaderinc`, a port of the map maker preview's three.js
  lighting / fog / sky reflections (`SkyforgePreviewLook`); check changes
  side by side with the preview (`pipeline/make_preview.py`). One change from
  it (owner asked): the panorama's bright pink patch behind the sun had hard
  straight edges (two-tone sky), so it's now a soft glow round the sun
  (`tools/smooth_sky_glow.py`; original in `sky/source/`). Grunts turn
  back from drops deeper than 3 m (`ledge_drop`). `?level=battle` / `toxic`.
- Toxic Works (owner asked; image-to-level's `slime_arena` package in
  `levels/slime_arena`, level 1 part 2 of 3; `ToxicWorks`, `?level=works`):
  the map maker preview's look with its own sky lighting
  (`sky/ibl_atlas.png`), effects as packaged. The squad arrives on
  Skyforge's lift coming down through the roof, controls held
  (`ElevatorLift.arrival`; the ceiling's collider got its exact shape so the
  shaft hole is open; the package's own elevator car is hidden). It's the
  game's start level (owner asked; DEPLOY drops the squad in on the lift).
  Opening shot (`ArrivalCamera`; owner asked for it closer, still dynamic):
  rides down the shaft just above the squad, breaks out under the roof,
  pulls out (staying under the ceiling's beams, < 21 m) into a crane shot
  circling the lift, then swoops round behind the player.
  Owner's latest map maker update (image-to-level 6f473a6, rebuilt here with
  its own `generate.py` + `package.py --game`; its 4 newest changes weren't in
  its committed export): the hall's 3 waves (4 grunts; 4 + 2 skirmishers;
  5 + 3; `WaveDirector` with `first_wave_placed` / `auto_start` off, started
  when the lift lands, hunting over `gameplay/navmesh.res`,
  `tools/bake_skyforge_navmesh.gd -- --level=works`) open the laser gate
  into the Works; 4 grunts + 2 skirmishers wait in the Works (no respawn);
  working assembly lines (skinned robot arms, running belts - the look's
  converted belt material is scrolled in `ToxicWorks`), the crusher (its
  pad kills), pads that surge up out of the slime, and the control terminal
  at their end: walking up to it opens the exit's laser gate. The package's
  `apply_effects.gd` needed compile fixes here (typed vars, a transform
  dropped upstream; a riser's colliders are looked up under their
  StaticBody3D too - the import names the body, not the shape, so the
  platforms were solid before rising). Slime / crusher / falling: player
  back to spawn, robots die. Exit hallway: "PART 3 COMING SOON" banner.
  Final rebuild (image-to-level 8bc3117, Stages 86-96, packaged here with
  `package.py --game`): turbine fan wind (package's `_wind`), rising
  shotgun platform with dripping goo, GIR in Core_Vat, drone swarm, window
  barriers. The shotgun platform (owner asked): its centre post is
  flattened into the deck (`ToxicWorks._shotgun_pad`, its colliders off)
  and the game's shotgun spawn pad (orange glow, gun spinning over it) rides
  the platform's bone up out of the slime; the package's own pickup area is
  unused. Laser gates (owner asked: "look amazingly better";
  `LaserGateFX`): the map maker's beams made invisible (blockers / frames
  unchanged) under camera-facing beams with white-hot cores, red glow,
  energy pulses and flicker, star flares and sparks at the emitters, a hex
  force field, sparks where a player presses in, and an overload / flash /
  collapse with a spark burst when they open.
  Turbine fan by the exit (owner asked: wind "facing wrong way", "instantly
  blow character off the edge no jumping over"): its streaks are drawn as
  lines along the wind (`wind_streak.gdshader`; the package's billboards
  stood them upright like rain). A player in its stream, from the walkway up
  to 9 m above the fan's centre, is knocked flying (`PlayerKnockdown`) and
  carried west off the Conduit Walk; the wind lets go at the stream's end so
  they drop into the slime, not onto the column base (`ToxicWorks.in_wind`,
  `_physics_process`). It still stops for good at the control terminal
  (package trigger). Robots keep the package's push.
  GIR in the Core_Vat tank (owner asked: "smaller but viewable by the
  player"): scaled to 0.6 (3.6 -> 2.2 m) about his middle and lifted 0.7 m
  (`ToxicWorks._shrink_gir`, `gir_scale` / `gir_lift`), so he floats clear
  of the tank's plinth band - whole body seen through the glass even from
  right up against it, head under the hood grate. Still drifts (the bob).
- Toxic barrels (owner's model, `assets/props/toxic_barrel`, original in
  `source/`; owner asked): two on Skyforge; shot, they explode (green
  cartoon blast, chain to barrels within 5 m) and leave burning green slime
  puddles with green cartoon flames that hurt anyone standing in them
  (`ToxicBarrel`, `ToxicBlast`, `ToxicSlime`).
- Skyforge rounds (owner asked): 1) the 4 placed grunts, 2) 8 grunts,
  3) 10 grunts, 4) 4 grunts + 2 skirmishers, 5) 6 + 4, 6) 4 + 4,
  7) 8 skirmishers; later rounds teleport in, each round from its own part
  of the map (`WaveDirector.wave_spawn_sets`: west, north + east, the
  south octagons, a west / north / east pincer, hub + turrets, anywhere),
  never more than 8 alive at once. Robots there always hunt the players
  (`hunt_players`): out of sight they follow paths over the level's baked
  navigation mesh (`gameplay/navmesh.res`, `tools/bake_skyforge_navmesh.gd`;
  hunting skirmishers don't hop while pathing). Then the lift rises out of
  the hub shaft; with the whole squad on it, it goes down and the next part
  of the level loads (`ElevatorLift`, `LevelFlow`, `LevelTransfer`; next
  part = the Toxic Works). Until it
  rises the lift is hidden (just the bottomless pit) and an invisible
  barrier rings the pit (`ShaftBarrier`, physics layer 4 "barrier": only
  players / robots collide with it, not shots or debris; off once the lift
  is up). The shaft's collision was opened (it was capped by the map
  export's convex hulls).

- Online co-op (owner asked, free): HOST / JOIN on character select, 4-digit
  room code (SHARE / ?join=<code> link), WebRTC phone to phone; phones find
  each other through ntfy.sh (free public message service, no account;
  the public PeerJS server stopped relaying) + Google STUN (no TURN relay
  yet: same Wi-Fi is reliable). `?netlog=1` shows the network log. The host's device runs the world (robots, barrels, waves, lift,
  level changes); each device runs its own character and its damage
  (`Net`, `NetPlayerInput`, `RobotEnemy.net_puppet`). Two-game test:
  `tests/run_net_pair.sh godot` (also in CI).

- HUD / menus: fill shapes with `HudStyle.fill` (batched), not
  `draw_colored_polygon`, and only redraw a panel when what it shows changes
  (spinning rings / the move stick are layers that rotate / move). Every
  polygon / AA line drawn makes graphics buffers again on each redraw: the
  HUD made ~400 a frame, and iPhone Safari closed the page after ~2.5 min.
- iPhone / iPad draw at 2x pixel ratio, not their screens' 3x (crash
  hunting: less GPU work and memory; a little softer). `?dpr=3` = full.

- Testing: the player can't die (`main.gd` `players_can_die = false`; hits
  still land, health can reach 0, no death / respawn). Owner asked for this
  to test; set it back to true to restore dying.

## Approved save points
- Branch `saved/approved-skirmisher-movement` (commit 536f448): the owner
  approved the skirmisher movement.
- Branch `saved/approved-2026-10-09` (commit 730b224): the owner said
  everything is good. It's the known-good state to compare against or roll
  back to. Never push to, move or delete `saved/*` branches.
- Branch `saved/approved-2026-10-10` (commit 139bd7b): the owner said it's
  good (cel muzzle flashes on every gun incl. grunts / skirmishers / black
  hole gun, the black hole portal, shotgun splats and blast rings). The
  newest known-good state.

## Shipping a change
- Test: `godot --headless --fixed-fps 60 --path . -s tests/movement_smoke_test.gd`
  (~1 min; must end `FAILURES: 0`); co-op: `tests/run_net_pair.sh godot`
  (must end `NET FAILURES: 0` twice).
- Commit and push to the working branch; `.github/workflows/web-build.yml`
  tests, exports and deploys (~3 min to live).
- When a build is live, always give the owner the link:
  https://harb666.github.io/CONSTRUCT-ERROR_V1/ (and a `?v=<anything>`
  variant to skip the phone's cache), plus the build label to look for.
