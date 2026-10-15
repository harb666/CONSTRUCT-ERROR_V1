# Checks: slime_arena - PASSED

errors 0 · warnings 2 · info 1

| metric | dev | mobile |
|---|---|---|
| file KB | 5898 | 3526 |
| triangles | 88610 | 103739 |
| draw calls (measured) | 4342 | 92 |
| visible draw calls (estimate) | - | 58.4 |
| GPU texture MB (estimate) | 22.63 | 7.01 |

Navigation: reachable 9616.0 of 49137.0 m² standable; components 443.
Camera: 1080 cameras, void rays 0, back faces 0.
Geometry: {'ERROR': 0, 'WARNING': 0, 'INTENTIONAL': 0} (checks/geometry.md)

## Issues (highest impact first)
- **warning** mobile draw calls 92 (> 80)
- **warning** 110266 triangles (> budget 40000)
- **info** 54 m² reachable floor has < 3.2 m headroom (cramped camera): Walkway_East_Floor, Walkway_North_Floor, Walkway_South_Floor, Walkway_West_Floor

Estimates are not device benchmarks; renders are the browser preview, not Godot.
