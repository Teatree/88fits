"""What Windows will show for a Windows build (pass 73): the icon sizes inside the exe, its version info (Properties ->
Details, Task Manager's name) and whether it carries a signature. ship.sh runs it after the PC export with
--expect-version <application/config/version> so an exe whose version is not the game's is caught.

  python tools/exe_info.py game/export/88fits.exe [--expect-version 0.59] [--ico-out dir]

Exit 1 only when --expect-version is given and the exe's FileVersion is not that version; a PC without the
`pefile` module skips the check (exit 0).
"""
import argparse
import os
import struct
import sys

try:
    import pefile
except ImportError:  # the check is a convenience, never a reason to stop a ship
    print("exe_info: the pefile module is missing (pip install pefile); skipped")
    sys.exit(0)


def read(path: str) -> dict:
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_RESOURCE"]])
    out = {"icons": [], "strings": {}, "groups": [], "icon_data": {}}
    res = pe.DIRECTORY_ENTRY_RESOURCE.entries if hasattr(pe, "DIRECTORY_ENTRY_RESOURCE") else []
    for t in res:
        for n in t.directory.entries:
            for leaf in n.directory.entries:
                d = leaf.data.struct
                data = pe.get_data(d.OffsetToData, d.Size)
                if t.id == pefile.RESOURCE_TYPE["RT_ICON"]:
                    out["icon_data"][n.id] = data
                elif t.id == pefile.RESOURCE_TYPE["RT_GROUP_ICON"]:
                    out["groups"].append(data)
    for g in out["groups"][:1]:
        count = struct.unpack_from("<H", g, 4)[0]
        for i in range(count):
            w, h, _cc, _r, _planes, bpp, size, iid = struct.unpack_from("<BBBBHHIH", g, 6 + i * 14)
            out["icons"].append((w or 256, h or 256, bpp, iid))
    pe.parse_data_directories()
    for fi in getattr(pe, "FileInfo", []) or []:
        for entry in fi:
            for st in getattr(entry, "StringTable", []) or []:
                for k, v in st.entries.items():
                    out["strings"][k.decode("utf-8", "replace")] = v.decode("utf-8", "replace")
    sec = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_SECURITY"]]
    out["signature"] = sec.Size
    pe.close()
    return out


def write_ico(info: dict, path: str) -> None:
    """The exe's first icon group as an .ico file (to look at what Explorer shows)."""
    entries = info["icons"]
    head = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    dirs, blobs = b"", b""
    for w, h, bpp, iid in entries:
        blob = info["icon_data"].get(iid, b"")
        dirs += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, bpp, len(blob), offset + len(blobs))
        blobs += blob
    with open(path, "wb") as f:
        f.write(head + dirs + blobs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("--expect-version", default="")
    ap.add_argument("--ico-out", default="")
    a = ap.parse_args()
    info = read(a.exe)
    s = info["strings"]
    sizes = ", ".join(str(w) for w, _h, _b, _i in info["icons"]) or "none"
    print("exe_info: icon %s px | version %s | %s | %s | signature %s" % (
        sizes, s.get("FileVersion", "?"), s.get("ProductName", "?"), s.get("CompanyName", "?"),
        ("present" if info["signature"] else "none")))
    if a.ico_out:
        os.makedirs(a.ico_out, exist_ok=True)
        write_ico(info, os.path.join(a.ico_out, os.path.splitext(os.path.basename(a.exe))[0] + ".ico"))
    if a.expect_version:
        want = a.expect_version.strip()
        parts = (want.split(".") + ["0", "0", "0", "0"])[:4]
        full = ".".join(str(int(p)) if p.isdigit() else p for p in parts)
        got = s.get("FileVersion", "")
        if got not in (want, full):
            print("exe_info: FileVersion %s is not the game's version %s" % (got or "(none)", want))
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
