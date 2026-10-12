# Portal Strike

> Play Counter-Strike: Source with the Aperture Science Handheld Portal Device, live see-through portal cameras, reverse-time killcams, and intelligent bot squads.

[![Platform](https://img.shields.io/badge/Platform-PC%20%7C%20Windows-blue.svg)](#requirements)
[![Engine](https://img.shields.io/badge/Engine-Source%20Engine%20(CS:S)-orange.svg)](#requirements)
[![Framework](https://img.shields.io/badge/Framework-SourceMod%20%26%20Metamod:Source-brightgreen.svg)](#requirements)
[![Version](https://img.shields.io/badge/Version-v1.6.0%20Release-purple.svg)](#overview)

---

## 👨‍💻 Creator & Community

- Creator: MrLuke1618
- YouTube: [@luke1618gamer](https://www.youtube.com/@luke1618gamer)
- TikTok: [@hoangcao2704](https://www.tiktok.com/@hoangcao2704)
- Public Distribution: Melty.gg & YouTube

---

## 🌌 Overview

Portal Strike brings the mind-bending physics and spatial traversal of Valve's *Portal* directly into *Counter-Strike: Source*. Designed as a pristine SourceMod plugin and asset integration engine, Portal Strike adds the Aperture Science Handheld Portal Device (ASHPD) to tactical 5v5 bomb defusal and hostage rescue rounds without altering core game binaries or breaking vanilla weapon balance.

---

## ⚠️ Dual-Game Requirements & Legal Architecture (Good to Know)

> [!IMPORTANT]
> Portal Strike requires legally owned copies of both Counter-Strike: Source and Portal on Steam.
> 
> To respect intellectual property and comply with Steam distribution guidelines:
> - Zero Copyrighted Valve Assets Bundled: Portal models (`portal1.mdl`, `portal2.mdl`, `v_portalgun.mdl`, `w_portalgun.mdl`), authentic Aperture audio cues, particle manifests, and material shaders are not bundled unlawfully in this repository.
> - Direct Local Extraction: When you run the automated installer (`launch_portal_strike.bat` or `package_portal_to_css.py`), the tool reads these assets directly from your own legally purchased Portal installation (`portal_pak_dir.vpk`) and maps them safely into your `cstrike/custom/portal_strike/` folder.
> - Pure Server Whitelist: An official `pure_server_whitelist.txt` is automatically placed into `cstrike/` to ensure your client never experiences model bounds disconnects or consistency kicks.

---

## 🔫 Core Features & Mechanics

### 🌀 The Portal Gun Arsenal & Mode-Toggle Architecture
- Dedicated Mode-Toggle: Press `[F]` or `[T]` (or execute `sm_portal_toggle` in console) to seamlessly switch between standard firearms and the Aperture Handheld Portal Device.
- Exclusive Dual-Portal Firing:
  - `MOUSE1` (+attack): Deploys Portal A (Blue for CT, Orange for T).
  - `MOUSE2` (+attack2): Deploys Portal B (Cyan for CT, Yellow for T).
- Independent Dual-Slot Tracking: Firing Portal A or Portal B updates only that portal slot, preserving active links across the battlefield.
- Instant Firearm Restoral: Switching back to firearm mode immediately restores weapon viewmodels and normal shooting mechanics with zero delay.

### 🎥 Live See-Through Portals (Render-to-Texture Cameras)
- Active portals deploy dynamic render-to-texture projection cameras (`point_camera` + `_rt_Camera`) coupled with custom `UnlitGeneric` glass shaders (`portal_1_dynamicmesh.vmt`, `portal_2_dynamicmesh.vmt`).
- Players and AI bots can visually peer through active portals in real time to scout corridors, bomb sites, and enemy positions before stepping through.

### ⏪ Cinematic Reverse-Time Killcam
- When a round ends, a cinematic replay camera (`point_viewcontrol`) activates for all connected players and spectators.
- The camera begins at the victim's fatal impact point and sweeps smoothly backward along the bullet vector to the killer's firing stance, recreating high-stakes Call of Duty-style final killcams with a clean, clutter-free HUD.

### 🎖️ Single-Bearer Team Rules & Dynamic Death Reallocation
- Strict Quota: Exactly one designated Portal Bearer per team can carry and operate the ASHPD at any given time.
- Priority Assignment: If a team contains human players, the human player is automatically designated as the team's Portal Bearer.
- Dynamic Reallocation: If a Portal Bearer falls in combat, the portal device is immediately reallocated to a surviving teammate with real-time HUD and audio notifications.

### 🌐 Universal Cross-Team Traversal & Authentic Fall Damage
- Open-Access Networks: Active portals function as universal traversal nodes. Both Counter-Terrorists and Terrorists (human players and AI bots alike) can freely traverse any portal pair.
- Conservation of Momentum: Entry velocity is transformed into the exit portal’s facing direction, allowing players and projectiles to fling across chasms.
- Grenade & Projectile Traversal: HE grenades, flashbangs, and smoke canisters physically pass through portals and detonate on the other side.
- Strict Fall Damage Enforcement: Downward vertical drops out of portals apply calculated impact velocities (`m_flFallVelocity`), triggering authentic Source engine fall damage (`DMG_FALL`).

### 🖥️ Dynamic Hardware Aspect Ratio Auto-Scaling
- On player connection, the server queries the client's screen ratio (`r_aspectratio`).
- Automatically adjusts HUD positioning and camera projection FOV across:
  - 16:9 (Standard Widescreen)
  - 16:10 (PC Gaming Displays)
  - 21:9 (Ultra-wide Monitors)
  - 4:3 (Retro CRT / Stretched Resolution)

---

## 🛠️ Repository & File Structure

```
portal_strike_release/
├── launch_portal_strike.bat   # Unified dynamic launcher (dual-game directory picker & automated installer)
├── package_portal_to_css.py   # Automated deployment engine (extracts Portal VPK -> maps into CS:S)
├── portal_strike.sp           # SourceMod plugin source code (v1.6.0)
├── portal_strike.smx          # Compiled SourceMod plugin binary (v1.6.0)
├── pure_server_whitelist.txt  # Server whitelist exempting ported Portal assets
├── tactical_bridge.py         # Tactical map bridge & nav sync
├── verify_assets.py           # Asset integrity & dual-game installation validator
├── verify_assets.bat          # 1-click batch asset verification runner
├── verify_all_maps.py         # Multi-map BSP geometry & navigation validator
├── vpk_inspector.py           # Native Source VPK parser & asset extractor
└── portal_strike/             # Clean custom mod structure ready for cstrike/custom/portal_strike/
    ├── materials/models/portals/  # Portal shaders (_rt_Camera UnlitGeneric)
    ├── scripts/                   # weapon_portalgun.txt & sound manifests
    └── botprofile.db             # AI bot tactical personality database
```

---

## 📋 System Requirements & Prerequisites

1. Counter-Strike: Source (Legally purchased & installed via Steam).
2. Portal (Legally purchased & installed via Steam to extract authentic Aperture sound, viewmodel, and particle assets).
3. Metamod:Source (v1.11+ or v1.12+ installed into `cstrike/addons/metamod/`).
4. SourceMod (v1.12+ installed into `cstrike/addons/sourcemod/`).
5. Python 3.8+ (Required for the automated asset packaging and deployment engine).

---

## 🚀 Quick Start & Installation

### Option A: 1-Click Automated Launcher (Recommended)
1. Download or clone this repository to your PC.
2. Run `launch_portal_strike.bat`.
3. Select Your Game Directories (if prompted or non-default):
   - Press `[D]` to open the Automated GUI Directory Picker. You will be prompted to select:
     1. Your Counter-Strike: Source directory (e.g., `SteamLibrary\steamapps\common\Counter-Strike Source`)
     2. Your Portal directory (e.g., `SteamLibrary\steamapps\common\Portal`)
   - Press `[I]` to run the Automated File Placement Engine. The script will:
     - Read authentic models (`portal1.mdl`, `portal2.mdl`, `v_portalgun.mdl`, `w_portalgun.mdl`) from your Portal VPK
     - Patch model bounding coordinates to prevent server bounds disconnects
     - Deploy see-through camera shaders (`portal_1_dynamicmesh.vmt`, `portal_2_dynamicmesh.vmt` -> `_rt_Camera`)
     - Deploy `portal_strike.smx` directly into `cstrike/addons/sourcemod/plugins/`
     - Deploy `pure_server_whitelist.txt` into `cstrike/`
4. Press `[0]` to launch CS:S to the Main Menu or select any map number to launch directly into a match with bots.

### Option B: Manual Installation
1. Ensure you have run `python package_portal_to_css.py --css "<PathToCSS>" --portal "<PathToPortal>"` to extract assets from your local Portal copy.
2. Copy `portal_strike.smx` into:
   ```
   <Counter-Strike Source>/cstrike/addons/sourcemod/plugins/portal_strike.smx
   ```
3. Copy the entire contents of `portal_strike/` into:
   ```
   <Counter-Strike Source>/cstrike/custom/portal_strike/
   ```
4. Copy `pure_server_whitelist.txt` into:
   ```
   <Counter-Strike Source>/cstrike/pure_server_whitelist.txt
   ```
5. Start Counter-Strike: Source and join any server or local map!

---

## 🎮 In-Game Controls & Commands

| Action | Control / Command | Description |
| :--- | :--- | :--- |
| Toggle Portal Gun | `[F]` or `[T]` | Seamlessly switch between firearm and ASHPD mode |
| Fire Portal A | `MOUSE1` (+attack) | Deploys Primary Portal (Blue for CT, Orange for T) |
| Fire Portal B | `MOUSE2` (+attack2) | Deploys Secondary Portal (Cyan for CT, Yellow for T) |
| Clear Portals | `sm_portal_clear` | Clears all active portals on the level |
| Aspect Scaling | `r_aspectratio` | Automatically polled on connect to scale FOV & HUD bounds |

---

## ⚖️ Credits & Legal Disclaimer

- Portal Strike is an independent community mod and gameplay experiment created by MrLuke1618.
- Built on top of AlliedModders' SourceMod and Metamod:Source frameworks.
- *Counter-Strike: Source* and *Portal* are registered trademarks and copyright © Valve Corporation.
- This project is not affiliated with, produced by, or endorsed by Valve Corporation. All portal models, sounds, and textures are extracted directly from the user's legally owned Steam installation of *Portal*.
