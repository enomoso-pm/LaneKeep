#!/usr/bin/env python3
"""Patches the copy of KeyboardShortcuts 2.4.0 in Vendor/ for a Command Line Tools build (build_app.sh).

1. Removes the #Preview blocks. Their macro plugin (PreviewsMacros) ships only with Xcode, and
   Recorder.swift has them outside #if DEBUG.
2. Takes the Localization folder away from SwiftPM and looks the strings up in the app's
   Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle, where build_app.sh copies them (and
   where an Xcode build has them). SwiftPM's command-line resource accessor looks only next to the
   app bundle and in the absolute build folder, and stops the app with fatalError when neither
   exists, which is what any other Mac would hit when the shortcut recorder shows its placeholder.

Every change checks that it applies exactly once, so a different KeyboardShortcuts version fails here
instead of building something else.

Usage: patch_keyboardshortcuts.py <Vendor/KeyboardShortcuts> <KeyboardShortcutsLocalizations.swift>
"""

import pathlib
import re
import shutil
import sys

root = pathlib.Path(sys.argv[1])
accessor = pathlib.Path(sys.argv[2])
sources = root / "Sources" / "KeyboardShortcuts"


def replace_once(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"{path.name}: expected one {old!r}, found {text.count(old)}")
    path.write_text(text.replace(old, new))


# 1. The previews: top-level `#Preview {` ... `}` blocks.
recorder = sources / "Recorder.swift"
text, removed = re.subn(r"^#Preview \{\n(?:.*\n)*?\}\n", "", recorder.read_text(), flags=re.MULTILINE)
if removed == 0:
    raise SystemExit("Recorder.swift: no #Preview blocks found")
recorder.write_text(text)
left = [p.name for p in sources.rglob("*.swift") if "#Preview" in p.read_text()]
if left:
    raise SystemExit(f"#Preview left in {left}")

# 2. The localized strings.
manifest = root / "Package.swift"
replace_once(manifest, '\tdefaultLocalization: "en",\n', "")
replace_once(
    manifest,
    '\t\t\tname: "KeyboardShortcuts",\n\t\t\tswiftSettings:',
    '\t\t\tname: "KeyboardShortcuts",\n\t\t\texclude: ["Localization"],\n\t\t\tswiftSettings:',
)
replace_once(sources / "Utilities.swift", "bundle: .module", "bundle: .keyboardShortcutsLocalizations")
left = [p.name for p in sources.rglob("*.swift") if ".module" in p.read_text()]
if left:
    raise SystemExit(f"Bundle.module still used in {left}")
shutil.copy(accessor, sources / accessor.name)

print(f"KeyboardShortcuts patched: {removed} previews removed, strings from the app's Resources")
