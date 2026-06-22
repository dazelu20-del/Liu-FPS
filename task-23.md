# task-23.md — "Last Circle" Game Design (Godot battle-royale slice)

> The plan for the AI agent to follow, the **Superpowers** way:
> brainstorm → plan (this file) → build → playtest → ship.
> Same method as task-11 and task-22 — new domain: a 3D game.

---

## 1. Overview
Build **Last Circle** — a small PUBG-style shooter in **Godot 4**:
a 3D arena, a real animated character model, bots that hunt you, a
shrinking safe zone, and **multiplayer** (host a match, friends join).
Last player standing wins.

## 2. Goals / Non-Goals
**Goals**
- A playable vertical slice of a battle royale: move, shoot, zone, win.
- A **real 3D character model** (downloaded, rigged, animated) in the game.
- Real **multiplayer**: one player hosts, others join by IP. Bots fill in.
- Clean Godot architecture a beginner can read: one scene per concept.

**Non-Goals (a slice, not PUBG)**
- No looting/inventory, no vehicles, no 100-player servers, no matchmaking.
- One arena, one weapon (hitscan rifle). More guns = roadmap.

## 3. The PUBG feature map — full game vs. our slice
| PUBG has | Our slice | Why this scope |
|---|---|---|
| 100 players, matchmaking | host + LAN/IP joiners + bots | the *mechanic* is identical |
| Huge island | one 120×120 m arena | level design ≠ engine work |
| Many weapons + attachments | one hitscan rifle | one done well teaches all |
| Shrinking blue zone | ✅ shrinking circle + damage | the signature mechanic |
| Loot, armor, heals | ❌ (roadmap) | pure additive content |
| Squads, voice | ❌ | out of scope |

## 4. Tech Stack & asset pipeline
| Layer | Choice | Why |
|-------|--------|-----|
| Engine | **Godot 4.5** | Free, lightweight, first-class GDScript + multiplayer |
| Language | **GDScript** | Python-like, perfect for beginners |
| Character | **CC0 rigged GLB** (KayKit/Quaternius) | real model, free license, no login |
| Animations | bundled clips (Idle/Run/Shoot) via **AnimationTree** | industry pattern |
| Sounds | none in MVP (roadmap) | keep the slice visual |

**Where game art comes from (teach all three):**
1. **CC0 packs** — kenney.nl, kaylousberg.com (KayKit), quaternius.com.
   GLB downloads, no account, free for any use. ← what we use
2. **Mixamo** — upload any humanoid model, auto-rig it, pick from 2,000+
   animations, export FBX. Free with an Adobe login.
3. **Blender** — model + rig your own (the real pipeline studios use).
   Export GLB → drop into Godot. The skill ceiling, not the MVP.

## 5. Architecture / Scene & script division
```
fps-game/
  project.godot          # input map, window, main scene
  scenes/
    main_menu.tscn       # Host / Join (IP) / Solo vs bots
    game.tscn            # arena root: floor, walls, cover, spawns, zone
    player.tscn          # CharacterBody3D + camera rig + model + gun ray
    bot.tscn             # same body, brain instead of camera
    hud.tscn             # health, ammo, alive count, zone timer, win text
  scripts/
    game.gd              # match flow: spawns, zone, win check  (the referee)
    player.gd            # input → move/aim/shoot   (only the local player)
    bot.gd               # FSM: wander → chase → shoot
    health.gd            # shared: HP, damage, death signal
    zone.gd              # shrinking circle + tick damage outside
    net.gd  (autoload)   # host/join, spawn players, RPCs
  assets/characters/     # the downloaded GLB models (CC0)
```
Rule of the architecture: **player.tscn and bot.tscn share the same body
and health** — a bot is a player with a different brain. The server (host)
is the referee: all damage and the zone run on the host only.

## 6. Multiplayer model (Godot high-level API)
- Host: `ENetMultiplayerPeer.create_server(9999)` · Join: `create_client(ip)`.
- A `MultiplayerSpawner` creates one player per connected peer;
  a `MultiplayerSynchronizer` on each player syncs position/rotation/anim.
- **Authority rule:** each peer controls its own player (input authority);
  the **host** owns truth: hit detection, HP, zone damage, win check —
  clients only *ask* (`shoot.rpc_id(1, ...)`) and get told the result.
- Bots exist only on the host; their state syncs down like any player.

## 7. Game rules (the contract)
- Rifle: hitscan ray from camera, 25 dmg, 0.15 s cooldown, 30-round mag,
  R to reload (1.2 s). Headshots ×2 (roadmap).
- HP 100, no regen. Death → spectator (orbit the arena), bots respawn off.
- Zone: full arena → shrinks toward a random center in 4 steps
  (radius 60 → 35 → 18 → 6 m, 25 s per step, 10 s warning between).
  Outside the circle: 5 HP/s. The circle is visible (translucent wall).
- Win: last living player/bot. HUD shows "WINNER WINNER 🍗" to the survivor.
- Match: menu → countdown 3 s → play → win screen → back to menu.

## 8. Task Breakdown (build in this order, run the game after each)
1. **Project + arena** — floor, walls, scattered cover boxes, lighting;
   a capsule player that walks/jumps/sprints (WASD + mouse).
2. **Shooting** — camera ray, muzzle flash, hit marker, damage to test
   dummies; ammo + reload.
3. **Real model** — import the CC0 GLB, attach to the player body,
   AnimationTree: Idle ↔ Run blend + Shoot one-shot.
4. **Bots** — NavigationRegion3D bake; FSM wander → chase (sees you within
   25 m) → shoot (within 18 m, imperfect aim).
5. **Zone** — shrinking circle, outside damage, HUD timer.
6. **Multiplayer** — host/join menu, player spawning, sync, host-authority
   damage; test with two instances on one machine.
7. **Match flow** — alive counter, death → spectate, win screen, restart.
8. **Playtest + ship** — solo vs 5 bots; 2-instance LAN match; export
   presets for Windows (.exe) / macOS.

## 9. Testing Plan (games test differently!)
- **Engine-level checks:** `godot --headless --import` (assets compile)
  and a boot smoke test — the game scene loads and `_ready` runs without
  errors in headless mode.
- **Rule tests (GUT-style, headless):** damage math, ammo/reload state,
  zone radius schedule, win detection — pure-logic scripts tested by a
  test scene that asserts and quits non-zero on failure.
- **Playtests (the real thing):** a scripted bot-only match must end with
  exactly one survivor; manual checklist per task (move/shoot/zone/join).

## 10. Definition of Done + Workflow
- A task is done when the game **runs** (no script errors), its checklist
  passes, and it's committed (`feat: bots chase and shoot`).
- Keep scripts under ~200 lines; one responsibility per script.

## 11. Ship it
- Godot → Project → Export → add **Windows Desktop** preset →
  `Last-Circle.exe` (plus macOS .app). Send the file to a friend,
  host a match, share your IP (or use a LAN), and play.
