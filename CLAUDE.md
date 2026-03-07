# CLAUDE.md — FTAP Script Project

## Project
- **Game:** Fling Things and People (FTAP) — Roblox game 6961824067
- **Executor:** Delta
- **Language:** Luau (Roblox scripting, school coding class)
- **Main file:** `Main.luau`

## Main.luau — "Verbal Sigma Master v4"

### UI
- **Library:** [Obsidian](https://github.com/deividcomsono/Obsidian) (`Library`, `ThemeManager`, `SaveManager`)
- `Library.Options` / `Library.Toggles` for all toggle/input state
- `Library:Notify()` wrapper: `Notify(title, desc, time)`

### Architecture
- All feature flags live in the `S` table (single global state object)
- Services cached at top: `LP`, `Players`, `RS`, `RunService`, `UIS`, `TweenSvc`, `Lighting`
- Remotes resolved async via `task.spawn` at startup (CharacterEvents, GrabEvents, MenuToys, etc.)
- Master loop: `RunService.Heartbeat` handles physicsAnchor, antiVoid, godMode, noclip, spin
- Helper functions: `getChar()`, `getRoot()`, `getHum()`, `getToyFolder()`, `disconnect(c)`, `getTarget()`

### Key Systems
| Section | What it does |
|---|---|
| **PhysicsAnchor (AntiGrab)** | Anchors HRP when `IsHeld=true`, allows WASD movement while anchored, fires Struggle + StopAllVelocity remotes |
| **AutoStruggle** | Separate loop — anchors all body parts + fires struggle remotes when grabbed or `PartOwner` detected on head |
| **AntiKickKunai** | Spawns NinjaShuriken toy, sticks it via StickyPartEvent to FirePlayerPart, blocks kunai kick |
| **AntiSticky** | 3-layer: disables StickyPartsTouchDetection script, sets CanTouch/CanQuery=false, destroys sticky welds |
| **AntiKickRag** | Loop fires RagdollRemote to cancel ragdoll state |
| **AntiVoid** | Tracks last safe Y; teleports back up if Y < -50 |
| **Blobman helpers** | Spawn/get blobman at sky position, auto-sit on own or nearest blobman |

### Game Remotes (ReplicatedStorage)
- `CharacterEvents`: `Struggle`, `RagdollRemote`
- `GrabEvents`: `SetNetworkOwner`, `CreateGrabLine`, `DestroyGrabLine`, `ExtendGrabLine`
- `MenuToys`: `SpawnToyRemoteFunction`, `DestroyToy`
- `GameCorrectionEvents`: `StopAllVelocity`
- `PlayerEvents`: `StickyPartEvent`
- Player values: `IsHeld` (BoolValue), `CanSpawnToy` (BoolValue)

### Feature Categories (S table flags)
- **Defense:** physicsAnchor, autoStruggle, antiVoid, godMode, antiExplosion, antiBurn, antiSticky, antiLag, antiPaint, antiGucci, antiBlobman, antiKickRag, antiKickKunai, antiInputLag, loopTP
- **Combat:** kickSpam, kickRagdoll, kickGrabTroll, kickBlob, dualKickLoop, ragdollSnow, loopKill, flingActive, destroyGucci, removeAK, removeAKAura, removeAIL, killGrab, throwStrength, masslessGrab
- **Player:** infJump, thirdPerson, spinChar, pcldESP, nameESP, noclip
- **Auras:** dualKickAura, kickAura1
- **Misc:** dreamyNight, noBarrier, packetLag, autoReset, triggerbot
- **Fun:** jerkOff, bang, followStare, fakeDeath, fakeLag, heartBuild, ufoShuriken

---

## Research Scripts

### `research/VerbalHub.luau`
Older predecessor using **Orion UI** (loaded from VerbalHubz/Verbal-Hub repo). Has fire flail animation, blobman grab loops, and basic kick/fling features. Code style is messier with obfuscated variable names (`vu1`, `vu2`...). Good reference for blobman logic and original Orion-based tab structure.

### `research/CosmicAura.luau`
"Cosmic Hub Auras" using a custom **OrionGod UI** fork. Focused on aura features (proximity-based kick auras). Has clean movement features: walkspeed (CFrame-based), infinite jump, noclip. Uses `_G` table for state. Good reference for aura radius logic.

### `research/Cosmic.luau`
"Cosmic Hub FTAP" — same OrionGod UI. More complete than CosmicAura. Includes `sendChatMessage()` helper (supports both legacy and TextChatService), full grab mechanics, movement, and a `getAllPlayers()` dropdown refresh pattern. Good reference for chat message sending and dropdown player lists.

### `research/Ye hub.luau`
The **OrionLib source code** itself (the UI library). Defines themes (Default, BruhE), feather icons loading, `MakeWindow`, `MakeTab`, `AddToggle`, `AddButton`, etc. Useful if you need to understand how Orion UI works internally or add custom elements.

### `research/Ftap.luau`
"Ragalic client" — uses **Obsidian UI** (same as Main.luau). Very similar architecture to Main.luau. Has tabs: Defense, Target, Grab, Player, Misc, Build, Fun, Keybinds, Notifications, Auras, UI Settings. Includes `deleteAllPaintParts`/`restorePaintParts` helpers. Best direct reference for Obsidian-based FTAP features.
