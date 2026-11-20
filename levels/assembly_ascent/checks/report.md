# Checks: assembly_ascent - PASSED

errors 0 · warnings 10 · info 2

| metric | dev | mobile |
|---|---|---|
| file KB | 7197 | 3964 |
| triangles | 110284 | 120862 |
| draw calls (measured) | 3956 | 229 |
| visible draw calls (estimate) | - | 112.3 |
| GPU texture MB (estimate) | 41.8 | 15.65 |

Navigation: reachable 5443.0 of 20640.0 m² standable; components 237.
Camera: - cameras, void rays -, back faces -.
Geometry: {'ERROR': 0, 'WARNING': 3, 'INTENTIONAL': 0} (checks/geometry.md)

## Issues (highest impact first)
- **warning** OuterWall_East_M05Vent_FrameSide_2 and OuterWall_East_M05Vent_Red share coplanar faces (0.07 m², different materials): z-fighting flicker [auto-repairable]
- **warning** OuterWall_East_M05Vent and OuterWall_East_M05Vent_Red share coplanar faces (0.19 m², different materials): z-fighting flicker [auto-repairable]
- **warning** mobile draw calls 229 (> 80)
- **warning** ~112 visible draw calls (estimate, > 60)
- **warning** Showcase_Pit_1_Lintel: walkable width ~1.0 m (< 3.0 m) - tight for strafing / the camera
- **warning** Showcase_Pit_1_Pillar_R: walkable width ~1.0 m (< 3.0 m) - tight for strafing / the camera
- **warning** Showcase_Pit_2_Lintel: walkable width ~1.0 m (< 3.0 m) - tight for strafing / the camera
- **warning** Showcase_Pit_2_Pillar_L: walkable width ~1.0 m (< 3.0 m) - tight for strafing / the camera
- **warning** enemy_arena: hazard 0.5 m away (< 3.0 m)
- **warning** 125388 triangles (> budget 40000)
- **info** dev GLB 7197 KB (> 6000)
- **info** 10 m² reachable floor has < 3.2 m headroom (cramped camera): Pod_Tube_1_Glass_03, Robot_Ring_Floor, Upper_Deck_Floor

Estimates are not device benchmarks; renders are the browser preview, not Godot.
