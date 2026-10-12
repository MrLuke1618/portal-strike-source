import struct
import os

vpk_path = r"D:\Steam\steamapps\common\Portal\portal\portal_pak_dir.vpk"
base_dir = os.path.dirname(vpk_path)

def parse_vpk(vpk_file):
    entries = []
    with open(vpk_file, "rb") as f:
        sig, ver, dir_size = struct.unpack("<III", f.read(12))
        if ver == 2:
            # VPK v2 has extra header fields: fileDataSectionSize, archiveMDNSectionSize, otherMDNSectionSize, signatureSectionSize
            f.read(16)
        
        while True:
            ext = b""
            while True:
                b = f.read(1)
                if not b or b == b"\x00":
                    break
                ext += b
            if not ext:
                break
            ext = ext.decode("latin1")

            while True:
                path = b""
                while True:
                    b = f.read(1)
                    if not b or b == b"\x00":
                        break
                    path += b
                if not path:
                    break
                path = path.decode("latin1")

                while True:
                    name = b""
                    while True:
                        b = f.read(1)
                        if not b or b == b"\x00":
                            break
                        name += b
                    if not name:
                        break
                    name = name.decode("latin1")

                    crc, preload_bytes, archive_index, entry_offset, entry_length, terminator = struct.unpack("<IHHIIH", f.read(18))
                    preload_data = f.read(preload_bytes) if preload_bytes > 0 else b""
                    
                    full_path = f"{path}/{name}.{ext}" if path != " " else f"{name}.{ext}"
                    entries.append({
                        "full_path": full_path,
                        "archive_index": archive_index,
                        "offset": entry_offset,
                        "length": entry_length,
                        "preload_bytes": preload_bytes,
                        "preload_data": preload_data
                    })
    return entries

if __name__ == "__main__":
    entries = parse_vpk(vpk_path)
    print(f"Total entries in portal_pak_dir.vpk: {len(entries)}")
    portal_gun_entries = [e for e in entries if any(k in e["full_path"].lower() for k in ["portalgun", "portals", "portal_particles", "game_sounds_weapons_portal", "game_sounds_portal"])]
    print(f"Matching Portal weapon/portal entries: {len(portal_gun_entries)}")
    for e in portal_gun_entries[:20]:
        print(f"  {e['full_path']} (archive: {e['archive_index']}, len: {e['length']})")
