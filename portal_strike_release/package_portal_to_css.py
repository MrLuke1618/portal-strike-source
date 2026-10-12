"""
Portal Strike: Automated Deployment Engine & Asset Packager
Extracts Portal viewmodels, worldmodels, materials, weapon scripts, sound manifests,
and particle systems from Portal VPK archives and deploys them directly into
Counter-Strike: Source (cstrike/custom/portal_strike and cstrike/addons/).
Automates directory mapping, model bounds patching, shader deployment, and plugin deployment.
"""

import os
import sys
import shutil
import struct
import argparse
import vpk_inspector

DEFAULT_PORTAL_DIR = r"D:\Steam\steamapps\common\Portal"
DEFAULT_CSS_DIR = r"E:\SteamLibrary\steamapps\common\Counter-Strike Source"

CREATOR_CREDENTIALS = (
    "Portal Strike - 2026 | Creator: MrLuke1618 | YouTube: @luke1618gamer | TikTok: @hoangcao2704"
)

INSTALLATION_GUIDE = f"""
================================================================================
                    PORTAL STRIKE - OFFICIAL INSTALLATION GUIDE
================================================================================
Creator: MrLuke1618
YouTube: https://www.youtube.com/@luke1618gamer
TikTok:  https://www.tiktok.com/@hoangcao2704
Distribution Portal: Melty.gg & YouTube
Version: 1.6.0 (SourceMod Hybrid Engine)

--------------------------------------------------------------------------------
1. SYSTEM REQUIREMENTS & PREREQUISITES
--------------------------------------------------------------------------------
- Counter-Strike: Source (Steam version, fully updated)
- Portal (Steam version installed to extract authentic Aperture assets)
- Metamod:Source (1.11+ installed in cstrike/addons/metamod/)
- SourceMod (1.12+ installed in cstrike/addons/sourcemod/)

--------------------------------------------------------------------------------
2. AUTOMATED DIRECTORY PICKER & 1-CLICK DEPLOYMENT
--------------------------------------------------------------------------------
To install or update Portal Strike automatically:
1. Run 'launch_portal_strike.bat'.
2. If your CS:S or Portal folders are on non-default Steam libraries, select [D]
   in the launcher to open the automated GUI Directory Picker.
3. Choose your 'Counter-Strike Source' folder and your 'Portal' folder.
4. Select [I] to run the Automated File Placement Engine. The script will:
   - Extract and port Portal gun models (v_portalgun.mdl, w_portalgun.mdl)
   - Deploy portal props (portal1.mdl, portal2.mdl) with oval collision hulls
   - Install see-through camera shaders (UnlitGeneric / _rt_Camera)
   - Copy 'portal_strike.smx' directly into cstrike/addons/sourcemod/plugins/
   - Configure pure_server_whitelist.txt to prevent consistency disconnects

--------------------------------------------------------------------------------
3. IN-GAME CONTROLS & GAMEPLAY
--------------------------------------------------------------------------------
- Toggle Portal Gun:       Press [F] or [T] (or type sm_portal_toggle in console)
- Primary Portal (Slot A): MOUSE1 (+attack) -> Deploys Blue (CT) or Orange (T)
- Secondary Portal (Slot B): MOUSE2 (+attack2) -> Deploys Cyan (CT) or Yellow (T)
- Universal Traversal:     Walk, run, or shoot through ANY active portal on the map
- Reversible Momentum:     Terminal velocity & fall momentum preserved
- Cinematic Killcam:       Universal reverse-time rewind replay at round end

--------------------------------------------------------------------------------
4. CREATOR & COMMUNITY
--------------------------------------------------------------------------------
Official Project: Portal Strike (2026)
Creator:          MrLuke1618
YouTube:          @luke1618gamer
TikTok:           @hoangcao2704
================================================================================
"""

def print_installation_guide():
    print(INSTALLATION_GUIDE)

def extract_vpk_entry(vpk_path, base_dir, entry):
    data = bytearray(entry["preload_data"])
    if entry["length"] > 0:
        if entry["archive_index"] == 0x7FFF:
            with open(vpk_path, "rb") as df:
                df.seek(entry["offset"])
                data.extend(df.read(entry["length"]))
        else:
            archive_name = f"portal_pak_{entry['archive_index']:03d}.vpk"
            archive_path = os.path.join(base_dir, archive_name)
            if os.path.exists(archive_path):
                with open(archive_path, "rb") as af:
                    af.seek(entry["offset"])
                    data.extend(af.read(entry["length"]))
            else:
                print(f"[Warn] Archive chunk not found: {archive_path}")
    return bytes(data)

def patch_model_bounds(file_bytes, filename):
    """
    Exempts ported Portal models (w_portalgun.mdl) from CS:S multiplayer server model bounds check.
    Clamps coordinates exceeding CS:S weapon mins (-15.0) to -14.9 to avoid disconnects.
    """
    if not filename.lower().endswith("w_portalgun.mdl") or len(file_bytes) < 152:
        return file_bytes
    
    data = bytearray(file_bytes)
    if data[:4] != b'IDST':
        return file_bytes
    
    clamped_count = 0
    for i in range(0, len(data) - 4, 4):
        fval = struct.unpack_from('<f', data, i)[0]
        if -50.0 < fval < -15.0:
            struct.pack_into('<f', data, i, -14.9)
            clamped_count += 1
            
    if clamped_count > 0:
        print(f"[Portal Strike] Model bounds exemption applied to {filename}: clamped {clamped_count} coordinates.")
    return bytes(data)

def deploy_plugin_and_assets(css_dir, portal_dir):
    """
    Automated deployment engine that maps directories and copies:
    1. portal_strike.smx -> cstrike/addons/sourcemod/plugins/
    2. portal1.mdl, portal2.mdl, v_portalgun.mdl, w_portalgun.mdl
    3. Material shaders and camera render target VMTs
    4. pure_server_whitelist.txt to exempt ported assets
    """
    cstrike_dir = os.path.join(css_dir, "cstrike")
    custom_dir = os.path.join(cstrike_dir, "custom", "portal_strike")
    addons_plugins_dir = os.path.join(cstrike_dir, "addons", "sourcemod", "plugins")
    addons_scripting_dir = os.path.join(cstrike_dir, "addons", "sourcemod", "scripting")

    script_dir = os.path.dirname(os.path.abspath(__file__))

    print("======================================================================")
    print("  PORTAL STRIKE: AUTOMATED FILE PLACEMENT & DEPLOYMENT ENGINE")
    print(f"  {CREATOR_CREDENTIALS}")
    print("======================================================================")
    print(f"[Deploy] Target CS:S cstrike directory: {cstrike_dir}")
    print(f"[Deploy] Source Portal directory:       {portal_dir}")

    os.makedirs(custom_dir, exist_ok=True)
    os.makedirs(addons_plugins_dir, exist_ok=True)
    os.makedirs(addons_scripting_dir, exist_ok=True)

    # 1. Deploy portal_strike.smx plugin
    local_smx = os.path.join(script_dir, "portal_strike.smx")
    local_sp = os.path.join(script_dir, "portal_strike.sp")
    target_smx = os.path.join(addons_plugins_dir, "portal_strike.smx")
    target_sp = os.path.join(addons_scripting_dir, "portal_strike.sp")

    if os.path.exists(local_smx):
        shutil.copy2(local_smx, target_smx)
        print(f"[Deploy] Successfully deployed portal_strike.smx -> {target_smx}")
    else:
        print(f"[Warn] Local portal_strike.smx not found at {local_smx}")

    if os.path.exists(local_sp):
        shutil.copy2(local_sp, target_sp)
        print(f"[Deploy] Synced portal_strike.sp source -> {target_sp}")

    # 2. Extract Portal assets from VPK
    portal_vpk = os.path.join(portal_dir, "portal", "portal_pak_dir.vpk")
    if not os.path.exists(portal_vpk):
        # Check if portal_dir directly points to portal folder
        alt_vpk = os.path.join(portal_dir, "portal_pak_dir.vpk")
        if os.path.exists(alt_vpk):
            portal_vpk = alt_vpk

    if os.path.exists(portal_vpk):
        print(f"[Deploy] Reading Portal VPK at: {portal_vpk}")
        entries = vpk_inspector.parse_vpk(portal_vpk)
        base_dir = os.path.dirname(portal_vpk)

        keywords = [
            "portalgun",
            "portals",
            "portal_particles",
            "game_sounds_weapons_portal",
            "particles_manifest",
            "v_models/v_portalgun",
            "w_models/portalgun",
            "materials/models/portals",
            "sound/weapons/portalgun",
            "particles/",
            "materials/particle/",
            "materials/effects/portal",
        ]

        blacklist = [
            "resource/",
            "scripts/vgui/",
            "vgui/",
            "background",
            "gamemenu",
            "mainmenu",
            "basemodpanel",
            "chapter",
            "gamepadui",
        ]

        target_entries = []
        for e in entries:
            fp = e["full_path"].lower()
            if any(b in fp for b in blacklist):
                continue
            if any(k in fp for k in keywords):
                target_entries.append(e)

        print(f"[Deploy] Extracting {len(target_entries)} Portal assets directly into {custom_dir}...")
        extracted_count = 0
        for e in target_entries:
            rel_path = e["full_path"].replace("/", os.sep)
            file_bytes = extract_vpk_entry(portal_vpk, base_dir, e)
            if not file_bytes:
                continue

            file_bytes = patch_model_bounds(file_bytes, os.path.basename(rel_path))

            out_file = os.path.join(custom_dir, rel_path)
            os.makedirs(os.path.dirname(out_file), exist_ok=True)
            with open(out_file, "wb") as f_out:
                f_out.write(file_bytes)
            extracted_count += 1

        print(f"[Deploy] Extracted {extracted_count} authentic Portal assets into cstrike/custom/portal_strike.")
    else:
        print(f"[Warn] Portal VPK archive not found at {portal_vpk}. Skipping direct VPK extraction.")

    # 3. Deploy and verify see-through dynamic camera shaders
    materials_portal_dir = os.path.join(custom_dir, "materials", "models", "portals")
    os.makedirs(materials_portal_dir, exist_ok=True)

    shader_vmt_content_1 = """"UnlitGeneric"
{
\t"$basetexture" "_rt_Camera"
\t"$surfaceprop" "glass"
\t"%compilepassbullets" 1
}
"""
    shader_vmt_content_2 = """"UnlitGeneric"
{
\t"$basetexture" "_rt_Camera"
\t"$surfaceprop" "glass"
\t"%compilepassbullets" 1
}
"""
    with open(os.path.join(materials_portal_dir, "portal_1_dynamicmesh.vmt"), "w", encoding="utf-8") as f:
        f.write(shader_vmt_content_1)
    with open(os.path.join(materials_portal_dir, "portal_2_dynamicmesh.vmt"), "w", encoding="utf-8") as f:
        f.write(shader_vmt_content_2)
    with open(os.path.join(materials_portal_dir, "portal_1_dynamicmesh_dx8.vmt"), "w", encoding="utf-8") as f:
        f.write(shader_vmt_content_1)
    with open(os.path.join(materials_portal_dir, "portal_2_dynamicmesh_dx8.vmt"), "w", encoding="utf-8") as f:
        f.write(shader_vmt_content_2)

    print("[Deploy] Installed see-through portal projection camera materials (_rt_Camera).")

    # 4. Deploy pure_server_whitelist.txt to exempt ported models and shaders
    whitelist_content = """whitelist
{
\t// Global model bounds & file consistency exemptions for ported Portal assets
\tmodels\\...		allow_from_disk
\tmaterials\\...		allow_from_disk
\tsound\\...		allow_from_disk
\tscripts\\...		allow_from_disk
\tparticles\\...		allow_from_disk
\tmaps\\...		allow_from_disk
}
"""
    whitelist_paths = [
        os.path.join(custom_dir, "pure_server_whitelist.txt"),
        os.path.join(custom_dir, "cfg", "pure_server_whitelist.txt"),
    ]
    for wp in whitelist_paths:
        os.makedirs(os.path.dirname(wp), exist_ok=True)
        with open(wp, "w", encoding="utf-8") as f:
            f.write(whitelist_content)

    print("[Deploy] Deployed pure_server_whitelist.txt consistency rules.")
    print("======================================================================")
    print("  AUTOMATED DEPLOYMENT COMPLETE! All Portal Strike assets ready.")
    print("======================================================================")

def main():
    parser = argparse.ArgumentParser(description="Portal Strike Packaging & Deployment Engine")
    parser.add_argument("--css", default=DEFAULT_CSS_DIR, help="Path to Counter-Strike Source root directory")
    parser.add_argument("--portal", default=DEFAULT_PORTAL_DIR, help="Path to Portal root directory")
    parser.add_argument("--guide", action="store_true", help="Print complete formatted Installation Guide")
    args = parser.parse_args()

    if args.guide:
        print_installation_guide()
        return

    deploy_plugin_and_assets(args.css, args.portal)

if __name__ == "__main__":
    main()
