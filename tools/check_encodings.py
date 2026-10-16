#!/usr/bin/env python3
"""
Check that every PowerShell script with non-ASCII content has a UTF-8 BOM.

**Why this is not fussiness.** Windows PowerShell 5.1 - which is what `powershell` runs on this
machine - reads a .ps1 as ANSI unless it starts with a UTF-8 BOM. A file holding an em dash, an
ellipsis or any Chinese is then decoded byte by byte into the system codepage, and the damage is
not cosmetic: the parser sees broken bytes inside what were string literals and reports

    The string is missing the terminator: ".
    Missing closing '}' in statement block or type definition.

pointing at lines that are perfectly correct. The whole script fails to run, and the reported line
is nowhere near the cause.

It bit tools/release.ps1 exactly that way. The file was written by a tool that emitted UTF-8
without a BOM; `pwsh` ran it fine, because PowerShell 7 reads UTF-8 by default, so the mistake
survived until the same script was run with `powershell`.

Usage:

    python tools/check_encodings.py          # check, exit 1 on a problem
    python tools/check_encodings.py --fix    # add the missing BOMs
"""
import sys
from pathlib import Path

BOM = b"\xef\xbb\xbf"
ROOT = Path(__file__).resolve().parent.parent

bad = []
good = []

for path in sorted(ROOT.rglob("*.ps1")):
    # Skip anything vendored or generated; only our own scripts are ours to fix.
    if any(part in {".git", "node_modules", "vendor", "build"} for part in path.parts):
        continue
    raw = path.read_bytes()
    has_bom = raw.startswith(BOM)
    body = raw[len(BOM):] if has_bom else raw
    try:
        body.decode("utf-8")
        decodes = True
    except UnicodeDecodeError:
        decodes = False
    non_ascii = sum(1 for b in body if b > 0x7F)

    rel = path.relative_to(ROOT)
    if has_bom:
        good.append(f"  ok    {rel}")
    elif non_ascii == 0 and decodes:
        # Pure ASCII cannot be misread, so a BOM is unnecessary. It is still harmless, and adding
        # one keeps every script the same shape.
        good.append(f"  ascii {rel}  (no BOM needed, but adding one is harmless)")
    else:
        bad.append((path, rel, non_ascii, decodes))

for line in good:
    print(line)

if not bad:
    print("\nall PowerShell scripts are safe to run with Windows PowerShell 5.1")
    raise SystemExit(0)

print()
for path, rel, non_ascii, decodes in bad:
    note = "" if decodes else "  *** and it is not even valid UTF-8 ***"
    print(f"  BAD   {rel}  ({non_ascii} byte(s) above 0x7F, no BOM){note}")
    print(f"        Windows PowerShell 5.1 will read this as ANSI and fail to parse it")

if "--fix" in sys.argv:
    print()
    for path, rel, _, _ in bad:
        text = path.read_bytes()
        if not text.startswith(BOM):
            path.write_bytes(BOM + text)
        print(f"  fixed {rel}")
    print("\nre-run without --fix to confirm")
    raise SystemExit(0)

print()
print("  fix with:  python tools/check_encodings.py --fix")
print("  or in PowerShell:")
print("    $t = [IO.File]::ReadAllText($f, (New-Object Text.UTF8Encoding($false)))")
print("    [IO.File]::WriteAllText($f, $t, (New-Object Text.UTF8Encoding($true)))")
raise SystemExit(1)
