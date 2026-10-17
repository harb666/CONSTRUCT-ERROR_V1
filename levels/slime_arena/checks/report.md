# Checks: slime_arena - PASSED

errors 0 · warnings 3 · info 2

| metric | dev | mobile |
|---|---|---|
| file KB | 6538 | 3996 |
| triangles | 101519 | 119239 |
| draw calls (measured) | 4811 | 150 |
| visible draw calls (estimate) | - | 78.8 |
| GPU texture MB (estimate) | 23.81 | 8.18 |

Navigation: reachable 9671.0 of 49109.0 m² standable; components 494.
Camera: 984 cameras, void rays 0, back faces 0.
Geometry: {'ERROR': 0, 'WARNING': 0, 'INTENTIONAL': 0} (checks/geometry.md)

## Issues (highest impact first)
- **warning** mobile draw calls 150 (> 80)
- **warning** ~79 visible draw calls (estimate, > 60)
- **warning** 126665 triangles (> budget 40000)
- **info** dev GLB 6538 KB (> 6000)
- **info** 48 m² reachable floor has < 3.2 m headroom (cramped camera): Conduit_Walk_Floor, Walkway_East_Floor, Walkway_South_Floor, Walkway_West_Floor

Estimates are not device benchmarks; renders are the browser preview, not Godot.
