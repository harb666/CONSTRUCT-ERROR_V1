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
- `scripts/main.gd` – `spawn_player(id, is_local)`; the future network layer plugs in here.
- `tests/movement_smoke_test.gd` – `godot --headless --path . -s tests/movement_smoke_test.gd`
