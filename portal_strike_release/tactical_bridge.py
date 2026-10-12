"""
Portal Strike: Tactical Bridge & Bot Management System
Bridges Counter-Strike: Source tactical game loops into the Portal host engine.
Parses BSP Lump 0 (entity lump), injects valid Portal spawn entities (info_player_start),
sets up AI relationships, manages squad spawning, team states, round logic, and buy simulation.
Applies global map patching and search path prioritization across all 20+ CS:S and custom maps.
"""

import os
import sys
import struct
import re
import glob

PORTAL_ROOT = r"D:\Steam\steamapps\common\Portal"
CSS_ROOT = r"E:\SteamLibrary\steamapps\common\Counter-Strike Source\cstrike"
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))

# Map Directories - Exclude CS:S custom maps so CS:S always runs pure vanilla BSPs with native game rules
PORTAL_BASE_MAPS = os.path.join(PORTAL_ROOT, "portal", "maps")
PORTAL_CUSTOM_MAPS = os.path.join(PORTAL_ROOT, "portal", "custom", "portal_strike", "maps")
PROJECT_MAPS = os.path.join(PROJECT_ROOT, "portal_strike", "maps")
STANDALONE_MAPS = os.path.join(PROJECT_ROOT, "maps")
MAP_TARGET_DIRS = [PORTAL_BASE_MAPS, PORTAL_CUSTOM_MAPS, PROJECT_MAPS, STANDALONE_MAPS]

# Config Directories - Pure isolated project repository only
PROJECT_CFG = os.path.join(PROJECT_ROOT, "portal_strike", "cfg")
CFG_OUTPUT_DIRS = [PROJECT_CFG]


def ensure_portal_spawn_in_bsp(bsp_path, target_dirs):
    """
    Checks if a .bsp map contains 'info_player_start' in Lump 0 (entity lump).
    If missing (as in CS:S multiplayer maps where only info_player_terrorist/counterterrorist exist),
    in-place patches the primary team spawn to 'info_player_start' (preserving exact byte length)
    so Portal's PutClientInServer can spawn the player without entity rejection errors.
    Directly overwrites active .bsp files across all specified target directories.
    """
    if not os.path.exists(bsp_path):
        return None

    with open(bsp_path, "rb") as f:
        data = bytearray(f.read())

    map_filename = os.path.basename(bsp_path)

    # Validate BSP header and extract Lump 0 (entity lump)
    if len(data) < 24:
        return bsp_path

    ident, version = struct.unpack("<4sI", data[:8])
    ent_offset, ent_len, ent_ver, ent_fourcc = struct.unpack("<IIII", data[8:24])

    ent_bytes = bytes(data[ent_offset:ent_offset + ent_len])
    has_start = b'"info_player_start"' in ent_bytes

    if not has_start:
        # In-place map primary team spawn inside Lump 0 to info_player_start
        old_target = None
        new_target = None

        if b'"info_player_terrorist"' in ent_bytes:
            old_target = b'"info_player_terrorist"'
            new_target = b'"info_player_start"    '  # 23 bytes exact match
        elif b'"info_player_counterterrorist"' in ent_bytes:
            old_target = b'"info_player_counterterrorist"'
            new_target = b'"info_player_start"            '  # 30 bytes exact match

        if old_target and new_target:
            rel_idx = ent_bytes.find(old_target)
            if rel_idx != -1:
                idx = ent_offset + rel_idx
                data[idx:idx + len(old_target)] = new_target
                print(f"[Bridge] Injected 'info_player_start' at Lump 0 offset {idx} in '{map_filename}'.")
            else:
                print(f"[Bridge] Warning: Spawn string found in lump but offset search failed for '{map_filename}'.")
        else:
            print(f"[Bridge] Notice: No standard team spawns found in Lump 0 for '{map_filename}'.")
    else:
        print(f"[Bridge] Map '{map_filename}' already contains valid 'info_player_start' in Lump 0.")

    # Write patched map data directly to all target directories
    for tdir in target_dirs:
        os.makedirs(tdir, exist_ok=True)
        out_file = os.path.join(tdir, map_filename)
        # Always write if target is missing or content differs
        try:
            with open(out_file, "wb") as f_out:
                f_out.write(data)
        except Exception as e:
            print(f"[Bridge] Error writing to {out_file}: {e}")

    return os.path.join(target_dirs[0], map_filename)


def parse_bsp_entities(bsp_path):
    """Reads Lump 0 (entities lump) from a Source engine .bsp file."""
    if not os.path.exists(bsp_path):
        return []
    with open(bsp_path, "rb") as f:
        ident, version = struct.unpack("<4sI", f.read(8))
        ent_offset, ent_len, ent_ver, ent_fourcc = struct.unpack("<IIII", f.read(16))
        f.seek(ent_offset)
        ent_data = f.read(ent_len).decode("latin1", errors="ignore")

    raw_ents = re.findall(r"\{([^}]+)\}", ent_data)
    entities = []
    for raw in raw_ents:
        ent = {}
        for line in raw.strip().splitlines():
            line = line.strip()
            m = re.match(r'"([^"]+)"\s+"([^"]*)"', line)
            if m:
                ent[m.group(1)] = m.group(2)
        if "classname" in ent:
            entities.append(ent)
    return entities


def generate_tactical_configs_for_map(map_name, bsp_path, output_dirs, is_active=False):
    """Extracts spawns from a BSP and creates dynamic spawn, universal <mapname>.cfg, and round configs."""
    entities = parse_bsp_entities(bsp_path) if bsp_path and os.path.exists(bsp_path) else []

    # Check for spawns (including newly mapped info_player_start)
    start_spawns = [e for e in entities if e.get("classname") == "info_player_start"]
    t_spawns = [e for e in entities if e.get("classname") == "info_player_terrorist"]
    ct_spawns = [e for e in entities if e.get("classname") == "info_player_counterterrorist"]
    bomb_sites = [e for e in entities if "bomb" in e.get("classname", "")]

    # If t_spawns was mapped to info_player_start, use start_spawns as team anchor
    if not t_spawns and start_spawns:
        t_spawns = start_spawns
    if not ct_spawns and start_spawns:
        ct_spawns = start_spawns

    # Fallbacks if map has no explicit spawns
    if not t_spawns:
        t_spawns = [{"origin": "0 0 64", "angles": "0 0 0"}]
    if not ct_spawns:
        ct_spawns = [{"origin": "256 0 64", "angles": "0 180 0"}]

    # Build spawn script for Terrorists (max 4 bots)
    spawn_t_lines = [
        f"// Portal Strike: Spawn Terrorist Militia Squad ({map_name})",
        f'echo "[Portal Strike] Spawning Terrorist Squad for {map_name}..."',
        "npc_create_equipment weapon_smg1",
    ]
    for i, sp in enumerate(t_spawns[:4]):
        orig = sp.get("origin", "0 0 0")
        ang = sp.get("angles", "0 0 0")
        parts = orig.split()
        if len(parts) == 3:
            orig = f"{parts[0]} {parts[1]} {float(parts[2]) + 16:.0f}"
        weapon = ["weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_pistol"][i % 4]
        spawn_t_lines.append(f"npc_create_equipment {weapon}")
        spawn_t_lines.append(
            f'ent_create npc_citizen origin "{orig}" angles "{ang}" citizentype 3 squadname "t_squad" targetname "bot_t_{i+1}"'
        )

    # Build spawn script for Counter-Terrorists (max 4 bots)
    spawn_ct_lines = [
        f"// Portal Strike: Spawn Counter-Terrorist Combine Squad ({map_name})",
        f'echo "[Portal Strike] Spawning Counter-Terrorist Squad for {map_name}..."',
        "npc_create_equipment weapon_ar2",
    ]
    for i, sp in enumerate(ct_spawns[:4]):
        orig = sp.get("origin", "0 0 0")
        ang = sp.get("angles", "0 0 0")
        parts = orig.split()
        if len(parts) == 3:
            orig = f"{parts[0]} {parts[1]} {float(parts[2]) + 16:.0f}"
        weapon = ["weapon_ar2", "weapon_shotgun", "weapon_smg1", "weapon_ar2"][i % 4]
        model = "models/combine_soldier_prisonguard.mdl" if i % 2 == 1 else "models/combine_soldier.mdl"
        spawn_ct_lines.append(f"npc_create_equipment {weapon}")
        spawn_ct_lines.append(
            f'ent_create npc_combine_s origin "{orig}" angles "{ang}" model "{model}" squadname "ct_squad" targetname "bot_ct_{i+1}"'
        )

    # Master spawn & AI relationship matrix for this map
    master_spawn_lines = [
        "// ==============================================================",
        f"//  Portal Strike: Tactical Bot Squad Spawner ({map_name})",
        "// ==============================================================",
        "sv_cheats 1",
        "",
        "// 1. Cleanup existing combatants",
        "ent_fire npc_combine_s kill",
        "ent_fire npc_citizen kill",
        "ent_fire npc_portal_turret_floor kill",
        "",
        "// 2. Spawn squads at map coordinates",
        f"exec spawn_squad_t_{map_name}.cfg",
        f"exec spawn_squad_ct_{map_name}.cfg",
        "",
        "// 3. Establish Faction Alliances & Hatred",
        "// CTs and Ts actively engage each other on sight",
        'ent_create ai_relationship subject npc_combine_s target npc_citizen disposition 1 rank 99 startactive 1',
        'ent_create ai_relationship subject npc_citizen target npc_combine_s disposition 1 rank 99 startactive 1',
        "",
        "// Default: Player is on Terrorist / Test Subject team (CTs hostile, Ts friendly)",
        'ent_create ai_relationship subject npc_combine_s target !player disposition 1 rank 99 startactive 1',
        'ent_create ai_relationship subject npc_citizen target !player disposition 3 rank 99 startactive 1',
        "",
        'play buttons/bell1.wav',
        f'echo "[Portal Strike] Tactical Squads spawned for {map_name}! CTs and Ts are in combat."',
    ]

    # Universal automated map configuration file (<mapname>.cfg)
    universal_map_cfg_lines = [
        "// ==============================================================",
        f"//  Portal Strike: Universal Automated Configuration ({map_name})",
        "// ==============================================================",
        f'echo "[Portal Strike] Executing automated map configuration for {map_name}..."',
        "sv_cheats 1",
        "con_enable 1",
        "developer 1",
        "hud_fastswitch 1",
        "",
        "// Global Model Bounds & Consistency Exemptions (Ported Portal Assets)",
        "sv_consistency 0",
        "sv_pure 0",
        "sv_pure_kick 0",
        "sv_pure_trace 0",
        "",
        "// 1. Natural Movement Controls & Controls Reset",
        "exec portal_strike.cfg",
        "",
        "// 2. Grant Authentic CS:S Arsenal & Dual-Portal Device",
        "exec tactical_loadout.cfg",
        "",
        "// 3. Initialize Tactical Round Controller",
        "exec round_controller.cfg",
        "",
        "// 4. Deploy Map-Specific Combatant Squads",
        f"exec spawn_bots_{map_name}.cfg",
        "",
        f'echo "[Portal Strike] Map {map_name} live: CS:S loadout, dual portal gun & bot squads active!"',
    ]

    for out_dir in output_dirs:
        os.makedirs(out_dir, exist_ok=True)
        # Map-specific spawn files
        with open(os.path.join(out_dir, f"spawn_squad_t_{map_name}.cfg"), "w", encoding="utf-8") as f:
            f.write("\n".join(spawn_t_lines) + "\n")
        with open(os.path.join(out_dir, f"spawn_squad_ct_{map_name}.cfg"), "w", encoding="utf-8") as f:
            f.write("\n".join(spawn_ct_lines) + "\n")
        with open(os.path.join(out_dir, f"spawn_bots_{map_name}.cfg"), "w", encoding="utf-8") as f:
            f.write("\n".join(master_spawn_lines) + "\n")
        # Universal auto-exec file for this map (<mapname>.cfg)
        with open(os.path.join(out_dir, f"{map_name}.cfg"), "w", encoding="utf-8") as f:
            f.write("\n".join(universal_map_cfg_lines) + "\n")

        # If this is the active launch map, also update standard spawn_bots.cfg
        if is_active:
            with open(os.path.join(out_dir, "spawn_squad_t.cfg"), "w", encoding="utf-8") as f:
                f.write("\n".join(spawn_t_lines) + "\n")
            with open(os.path.join(out_dir, "spawn_squad_ct.cfg"), "w", encoding="utf-8") as f:
                f.write("\n".join(spawn_ct_lines) + "\n")
            with open(os.path.join(out_dir, "spawn_bots.cfg"), "w", encoding="utf-8") as f:
                f.write("\n".join(master_spawn_lines) + "\n")

    return len(t_spawns), len(ct_spawns), len(bomb_sites)


def generate_static_tactical_modules(output_dirs):
    """Generates team, round, loadout, and buy menu simulation scripts using native Portal syntax."""
    
    # Authentic CS:S Tactical Loadout paired with Aperture Handheld Portal Device
    tactical_loadout_content = """// ==============================================================
//  Portal Strike: Authentic Tactical Skirmish Loadout
// ==============================================================
sv_cheats 1

// Global Model Bounds & Consistency Exemptions (Ported Portal Assets)
sv_consistency 0
sv_pure 0
sv_pure_kick 0
sv_pure_trace 0

// 1. Natural Movement Controls & Binding Resets (Strip movement hooks)
alias +ps_forward ""
alias -ps_forward ""
alias +ps_back ""
alias -ps_back ""
alias +ps_moveleft ""
alias -ps_moveleft ""
alias +ps_moveright ""
alias -ps_moveright ""

-forward
-back
-moveleft
-moveright
-jump
-duck
-speed

bind "w" "+forward"
bind "s" "+back"
bind "a" "+moveleft"
bind "d" "+moveright"
bind "SPACE" "+jump"
bind "CTRL" "+duck"
bind "SHIFT" "+speed"

// 2. Lock Native Portal Controls (Blue / Orange Portals)
-attack
-attack2
bind "MOUSE1" "+attack"
bind "MOUSE2" "+attack2"

// 3. Aperture HEV Armor & Tactical Suit
give item_suit
give item_battery
give item_battery
give item_battery
give item_battery
give item_healthkit

// 4. Aperture Handheld Portal Device (Dual-Portal Upgrade)
give weapon_portalgun
upgrade_portalgun
use weapon_portalgun

// 5. Authentic Counter-Strike: Source Tactical Arsenal
// Melee & Sidearms
give weapon_knife
give weapon_usp
give weapon_glock18
give weapon_deagle
give weapon_p228
give weapon_elite
give weapon_fiveseven

// Submachine Guns
give weapon_mp5navy
give weapon_tmp
give weapon_mac10
give weapon_ump45
give weapon_p90

// Assault & Tactical Rifles
give weapon_galil
give weapon_famas
give weapon_ak47
give weapon_m4a1
give weapon_sg552
give weapon_aug

// Precision Sniper Rifles
give weapon_scout
give weapon_awp
give weapon_g3sg1
give weapon_sg550

// Tactical Shotguns & Heavy Support
give weapon_m3
give weapon_xm1014
give weapon_m249

// Tactical Ordnance
give weapon_hegrenade
give weapon_flashbang
give weapon_smokegrenade

// 6. Tactical Ammunition Reserves
give item_ammo_pistol_large
give item_ammo_smg1_large
give item_ammo_ar2_large
give item_box_buckshot
give item_ammo_357_large

// 7. Equip Aperture Handheld Portal Device as Default Primary
use weapon_portalgun

echo "[Portal Strike] Tactical Loadout active: ASHPD (Blue/Orange) & CS:S Arsenal equipped!"
echo "[Portal Strike] Controls locked: MOUSE1=Blue, MOUSE2=Orange, W/A/S/D natural movement."
"""

    # Master portal_strike.cfg
    portal_strike_content = """// ==============================================================
//        PORTAL STRIKE: TACTICAL APERTURE SKIRMISH CFG
// ==============================================================
echo "=========================================================="
echo "          [PORTAL STRIKE] TACTICAL PORTAL HYBRID          "
echo "=========================================================="

// Server & Developer Engine Settings
sv_cheats 1
con_enable 1
developer 1
sv_lan 1
sv_timeout 999999
hud_fastswitch 1

// Global Model Bounds & Consistency Exemptions (Ported Portal Assets)
sv_consistency 0
sv_pure 0
sv_pure_kick 0
sv_pure_trace 0

// Tactical Game Loop CVars
mp_roundtime 2.5
mp_buytime 0.25
mp_startmoney 16000

// Clean Standard Movement Controls (NO movement hooks or ghost inputs)
-forward
-back
-moveleft
-moveright
-jump
-duck
-speed
bind "w" "+forward"
bind "s" "+back"
bind "a" "+moveleft"
bind "d" "+moveright"
bind "SPACE" "+jump"
bind "CTRL" "+duck"
bind "SHIFT" "+speed"

// Lock Native Portal Mouse Controls (Blue / Orange Portals)
-attack
-attack2
bind "MOUSE1" "+attack"
bind "MOUSE2" "+attack2"

// Execute Tactical Loadout & Round Controller
exec tactical_loadout.cfg
exec round_controller.cfg

// Tactical Buy Menu & Management Keys
bind "b" "exec buy_menu.cfg"
bind "f6" "exec tactical_loadout.cfg; play items/ammo_pickup"
bind "f7" "exec restart_round.cfg"
bind "f8" "exec spawn_bots.cfg"

// Quick Map Switch Keybindings
bind "f1" "map de_aztec"
bind "f2" "map cs_assault"
bind "f3" "map portal_dust2"
bind "f4" "map cs_compound"
bind "f5" "map cs_militia"

echo "[Portal Strike] Controls restored: W/A/S/D normal, MOUSE1=Blue Portal, MOUSE2=Orange Portal."
echo "[Portal Strike] Press 'B' to open Tactical Buy Menu."
echo "[Portal Strike] Hotkeys: F6=Restock, F7=Restart Round, F8=Respawn Bots"
echo "[Portal Strike] Map Keys: F1=Aztec, F2=Assault, F3=Dust2, F4=Compound, F5=Militia"
"""

    # Team Selection Module
    join_t_content = """// Portal Strike: Join Terrorist / Aperture Test Subject Team
echo "[Portal Strike] You have joined the TERRORIST Militia (Aperture Test Subjects)!"
ent_create ai_relationship subject npc_combine_s target !player disposition 1 rank 99 startactive 1
ent_create ai_relationship subject npc_citizen target !player disposition 3 rank 99 startactive 1
play radio/com_go.wav
"""

    join_ct_content = """// Portal Strike: Join Counter-Terrorist / Aperture Security Team
echo "[Portal Strike] You have joined the COUNTER-TERRORIST Combine Squad!"
ent_create ai_relationship subject npc_combine_s target !player disposition 3 rank 99 startactive 1
ent_create ai_relationship subject npc_citizen target !player disposition 1 rank 99 startactive 1
play radio/ct_affirm.wav
"""

    join_solo_content = """// Portal Strike: Join Free-For-All (Solo Sandbox)
echo "[Portal Strike] Free-For-All Active! Both CT and T squads are hostile to you!"
ent_create ai_relationship subject npc_combine_s target !player disposition 1 rank 99 startactive 1
ent_create ai_relationship subject npc_citizen target !player disposition 1 rank 99 startactive 1
play radio/locknload.wav
"""

    # Round Controller Module
    round_controller_content = """// Portal Strike: Round Controller & Objective Tracker
echo "=========================================================="
echo "          [ROUND CONTROLLER] TACTICAL SKIRMISH CLOCK       "
echo "=========================================================="
mp_roundtime 2.5
mp_freezetime 3

// Round Restart Key
bind "f7" "exec restart_round.cfg"

echo "[Portal Strike] Press 'F7' at any time to restart round and respawn bot squads."
"""

    restart_round_content = """// Portal Strike: Reset Round
echo "[Portal Strike] === ROUND RESTARTING ==="
play radio/rounddraw.wav

// Clear corpses and re-equip player
exec tactical_loadout.cfg

// Respawn both squads at authentic map spawns
exec spawn_bots.cfg

echo "[Portal Strike] Round Reset Complete! Tactical squads deployed."
"""

    # Buy Menu Module (Authentic CS:S weapon syntax)
    buy_menu_content = """// ==============================================================
//        PORTAL STRIKE: TACTICAL BUY SYSTEM SIMULATION
// ==============================================================
echo " "
echo "=============================================================="
echo "              [PORTAL STRIKE] CS:S BUY MENU                   "
echo "=============================================================="
echo "  [1] Tactical USP + Handheld Portal Device (Default)"
echo "  [2] MP5 Navy Rush Package (ASHPD + MP5 + Armor)"
echo "  [3] M4A1 Tactical Carbine (ASHPD + M4A1 + Armor)"
echo "  [4] AK-47 Assault Rifle (ASHPD + AK-47 + Armor)"
echo "  [5] AWP Heavy Sniper Rifle (ASHPD + AWP + Armor)"
echo "  [6] Full Tactical Armor & Health Restock (+100 Armor)"
echo "  [7] Spawn Squads: Reinforce / Deploy Bot Combatants"
echo "  [8] Join Team: Terrorists (Allied Militia)"
echo "  [9] Join Team: Counter-Terrorists (Allied Combine)"
echo "  [0] Close Buy Menu"
echo "=============================================================="
echo "  Press 1-9 or 0 to select..."
echo " "

alias "buy_slot1" "give weapon_usp; give weapon_portalgun; upgrade_portalgun; use weapon_portalgun; play items/ammo_pickup; buy_close; echo '[BUY] Tactical USP & ASHPD Equipped!'"
alias "buy_slot2" "give weapon_mp5navy; give item_ammo_smg1_large; give item_battery; use weapon_mp5navy; play items/ammo_pickup; buy_close; echo '[BUY] MP5 Navy Package Purchased!'"
alias "buy_slot3" "give weapon_m4a1; give item_ammo_ar2_large; give item_battery; use weapon_m4a1; play items/ammo_pickup; buy_close; echo '[BUY] M4A1 Carbine Purchased!'"
alias "buy_slot4" "give weapon_ak47; give item_ammo_ar2_large; give item_battery; use weapon_ak47; play items/ammo_pickup; buy_close; echo '[BUY] AK-47 Rifle Purchased!'"
alias "buy_slot5" "give weapon_awp; give item_ammo_357_large; give item_battery; use weapon_awp; play items/ammo_pickup; buy_close; echo '[BUY] AWP Sniper Rifle Purchased!'"
alias "buy_slot6" "give item_suit; give item_battery; give item_battery; give item_battery; give item_battery; give item_healthkit; play items/battery_pickup; buy_close; echo '[BUY] Kevlar Armor & Health Restocked!'"
alias "buy_slot7" "exec spawn_bots.cfg; buy_close"
alias "buy_slot8" "exec join_t.cfg; buy_close"
alias "buy_slot9" "exec join_ct.cfg; buy_close"
alias "buy_close" "bind 1 slot1; bind 2 slot2; bind 3 slot3; bind 4 slot4; bind 5 slot5; bind 6 slot6; bind 7 slot7; bind 8 slot8; bind 9 slot9; bind 0 slot10; echo '[Portal Strike] Buy Menu Closed.'"

bind "1" "buy_slot1"
bind "2" "buy_slot2"
bind "3" "buy_slot3"
bind "4" "buy_slot4"
bind "5" "buy_slot5"
bind "6" "buy_slot6"
bind "7" "buy_slot7"
bind "8" "buy_slot8"
bind "9" "buy_slot9"
bind "0" "buy_close"
"""

    autoexec_content = """// ==============================================================
//  Portal Strike: CS:S Primary Host Autoexec Configuration
// ==============================================================
// Global Model Bounds & Consistency Exemptions (Ported Portal Assets)
sv_consistency 0
sv_pure 0
sv_pure_kick 0
sv_pure_trace 0

sv_cheats 1
con_enable 1
developer 1

// Execute Master Portal Strike Configuration
exec portal_strike.cfg
"""

    server_content = """// ==============================================================
//  Portal Strike: CS:S Primary Host Server Configuration
// ==============================================================
// Disable model bounds and server consistency enforcement
sv_consistency 0
sv_pure 0
sv_pure_kick 0
sv_pure_trace 0

sv_lan 1
sv_cheats 1
maxplayers 16
"""

    listenserver_content = """// ==============================================================
//  Portal Strike: CS:S Listen Server Configuration
// ==============================================================
// Listen server consistency exemption for local single-player / bot skirmishes
sv_consistency 0
sv_pure 0
sv_pure_kick 0
sv_pure_trace 0

sv_cheats 1
"""

    whitelist_content = """whitelist
{
	// Global model bounds & file consistency exemptions for ported Portal assets
	models\\...		allow_from_disk
	materials\\...		allow_from_disk
	sound\\...		allow_from_disk
	scripts\\...		allow_from_disk
	particles\\...		allow_from_disk
	maps\\...		allow_from_disk
	resource\\...		allow_from_disk
}
"""

    for out_dir in output_dirs:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "tactical_loadout.cfg"), "w", encoding="utf-8") as f:
            f.write(tactical_loadout_content)
        with open(os.path.join(out_dir, "portal_strike.cfg"), "w", encoding="utf-8") as f:
            f.write(portal_strike_content)
        with open(os.path.join(out_dir, "autoexec.cfg"), "w", encoding="utf-8") as f:
            f.write(autoexec_content)
        with open(os.path.join(out_dir, "server.cfg"), "w", encoding="utf-8") as f:
            f.write(server_content)
        with open(os.path.join(out_dir, "listenserver.cfg"), "w", encoding="utf-8") as f:
            f.write(listenserver_content)
        with open(os.path.join(out_dir, "pure_server_whitelist.txt"), "w", encoding="utf-8") as f:
            f.write(whitelist_content)
        parent_dir = os.path.dirname(out_dir)
        if os.path.exists(parent_dir):
            with open(os.path.join(parent_dir, "pure_server_whitelist.txt"), "w", encoding="utf-8") as f:
                f.write(whitelist_content)
        with open(os.path.join(out_dir, "join_t.cfg"), "w", encoding="utf-8") as f:
            f.write(join_t_content)
        with open(os.path.join(out_dir, "join_ct.cfg"), "w", encoding="utf-8") as f:
            f.write(join_ct_content)
        with open(os.path.join(out_dir, "join_solo.cfg"), "w", encoding="utf-8") as f:
            f.write(join_solo_content)
        with open(os.path.join(out_dir, "round_controller.cfg"), "w", encoding="utf-8") as f:
            f.write(round_controller_content)
        with open(os.path.join(out_dir, "restart_round.cfg"), "w", encoding="utf-8") as f:
            f.write(restart_round_content)
        with open(os.path.join(out_dir, "buy_menu.cfg"), "w", encoding="utf-8") as f:
            f.write(buy_menu_content)


def discover_all_maps():
    """Finds all available CS:S, local, and custom maps across all directories."""
    found_maps = {}

    # 1. Official Mounted CS:S maps
    for m in glob.glob(os.path.join(CSS_ROOT, "maps", "*.bsp")):
        name = os.path.splitext(os.path.basename(m))[0]
        found_maps[name] = m

    # 2. Local standalone project maps
    for m in glob.glob(os.path.join(PROJECT_MAPS, "*.bsp")):
        name = os.path.splitext(os.path.basename(m))[0]
        found_maps[name] = m

    # 3. Portal custom maps
    for m in glob.glob(os.path.join(PORTAL_CUSTOM_MAPS, "*.bsp")):
        name = os.path.splitext(os.path.basename(m))[0]
        found_maps[name] = m

    # 4. Standalone root maps
    for m in glob.glob(os.path.join(STANDALONE_MAPS, "*.bsp")):
        name = os.path.splitext(os.path.basename(m))[0]
        found_maps[name] = m

    return found_maps


def sweep_and_patch_all_maps(active_map=None):
    """
    Direct Overwrite & Patching Sweep across all 20+ detected CS:S and custom maps.
    Ensures every map has info_player_start injected in Lump 0 and deployed across:
    - portal/maps/ (Host engine primary directory)
    - portal/custom/portal_strike/maps/ (Custom mount)
    - portal_strike/maps/ (Project standalone package)
    - maps/ (Standalone root)
    Generates universal <mapname>.cfg and squad spawner configs for every map.
    """
    all_maps = discover_all_maps()
    print(f"[Bridge] Starting Global Map Patching & Config Sweep across {len(all_maps)} detected maps...")

    count_patched = 0
    for map_name, bsp_path in sorted(all_maps.items()):
        is_active = (map_name == active_map)
        patched_path = ensure_portal_spawn_in_bsp(bsp_path, MAP_TARGET_DIRS)
        actual_path = patched_path or bsp_path
        generate_tactical_configs_for_map(map_name, actual_path, CFG_OUTPUT_DIRS, is_active=is_active)
        count_patched += 1

    generate_static_tactical_modules(CFG_OUTPUT_DIRS)
    print(f"[Bridge] Comprehensive sweep complete: {count_patched} maps patched & universal configs deployed.")


def prepare_map_bridge(map_name):
    """Finds the map's BSP, ensures info_player_start is present, and generates tactical bridge scripts."""
    print(f"[Bridge] Preparing Tactical Environment for: {map_name}")
    sweep_and_patch_all_maps(active_map=map_name)
    return True


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "--all"
    if target == "--all":
        sweep_and_patch_all_maps()
    else:
        prepare_map_bridge(target)
