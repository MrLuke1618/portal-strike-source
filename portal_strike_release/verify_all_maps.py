import struct, os, glob

dirs_to_check = {
    "Portal Base Maps (portal/maps)": r"D:\Steam\steamapps\common\Portal\portal\maps",
    "Portal Custom Maps (custom/portal_strike/maps)": r"D:\Steam\steamapps\common\Portal\portal\custom\portal_strike\maps",
    "Project Standalone Maps (portal_strike/maps)": r"D:\STUFF\Game Mashup\projects\portal_strike\portal_strike\maps",
}

for label, d in dirs_to_check.items():
    print(f"\n=== {label} ===")
    maps = glob.glob(os.path.join(d, "*.bsp"))
    print(f"Total maps found: {len(maps)}")
    missing_start = []
    for p in sorted(maps):
        with open(p, 'rb') as f:
            f.seek(8)
            ent_offset, ent_len = struct.unpack('<II', f.read(8))
            f.seek(ent_offset)
            ent_bytes = f.read(ent_len)
        s = b'"info_player_start"' in ent_bytes
        if not s and "test_" not in os.path.basename(p):
            missing_start.append(os.path.basename(p))
    if missing_start:
        print(f"FAILED: Missing info_player_start in: {missing_start}")
    else:
        print(f"SUCCESS: All {len(maps)} playable maps have valid info_player_start in Lump 0!")

print("\n=== Universal <mapname>.cfg check in Portal custom cfg ===")
cfg_dir = r"D:\Steam\steamapps\common\Portal\portal\custom\portal_strike\cfg"
cfgs = glob.glob(os.path.join(cfg_dir, "*.cfg"))
print(f"Total .cfg files in custom cfg: {len(cfgs)}")
map_cfgs = [f for f in cfgs if not os.path.basename(f).startswith("spawn_") and not os.path.basename(f) in ["tactical_loadout.cfg", "portal_strike.cfg", "buy_menu.cfg", "round_controller.cfg", "restart_round.cfg", "join_t.cfg", "join_ct.cfg", "join_solo.cfg"]]
print(f"Map specific configurations created: {len(map_cfgs)}")
for m in sorted(map_cfgs)[:10]:
    print(" ", os.path.basename(m))
