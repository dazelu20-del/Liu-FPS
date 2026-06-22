# Last Circle — a battle-royale slice in Godot 4 (task-23)

A small PUBG-style shooter built the task-23 way: a real animated 3D
character (CC0 KayKit model), bots with a wander→chase→shoot brain, a
shrinking zone, host/join multiplayer, and a last-one-standing win.

## Play it

Open the folder in **Godot 4.5+** (verified on 4.6.3) and press ▶ — or from a terminal:

```bash
godot --path .                 # main menu: Solo / Host / Join
```

WASD move · mouse aim · click shoot · R reload · Shift sprint ·
Space jump · Esc release mouse.

**Multiplayer:** one player clicks *Host match*; friends on the same
network enter the host's IP and click *Join*.

## Test it (headless — no window needed)

```bash
godot --headless --path . res://tests/test_rules.tscn   # rule tests
godot --headless --path . res://scenes/game.tscn -- --smoke      # boots + bots
godot --headless --path . res://scenes/game.tscn -- --botmatch   # full bot match → 1 survivor
```

## Ship it

Project → Export → add the **Windows Desktop** preset → `Last-Circle.exe`
(install export templates once via the editor when prompted).

## Design

See [task-23.md](task-23.md) — the PUBG-vs-slice feature map, the
asset pipeline (CC0 packs / Mixamo / Blender), and the host-as-referee
multiplayer model.
