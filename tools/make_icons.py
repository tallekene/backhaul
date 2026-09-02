#!/usr/bin/env python3
"""Re-render the launcher icon at every size the manifest's devices need.

Reads the resources-launcher-<w>-<h> directories that monkey.jungle already
references and regenerates the PNG in each from art/launcher.svg, so editing
the SVG is the only thing needed to change the icon everywhere.

Requires rsvg-convert (librsvg).
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG = os.path.join(ROOT, "art", "launcher.svg")

DRAWABLES_XML = (
    '<drawables>\n'
    '  <bitmap id="LauncherIcon" filename="launcher_icon.png" />\n'
    '</drawables>\n'
)


def main() -> int:
    if not os.path.exists(SVG):
        print(f"missing {SVG}", file=sys.stderr)
        return 1

    sizes = set()
    for name in os.listdir(ROOT):
        m = re.fullmatch(r"resources-launcher-(\d+)-(\d+)", name)
        if m:
            sizes.add((int(m.group(1)), int(m.group(2))))

    # Plus the shared fallback used by any device without an explicit size.
    for w, h in sorted(sizes):
        out = os.path.join(ROOT, f"resources-launcher-{w}-{h}", "drawables")
        os.makedirs(out, exist_ok=True)
        subprocess.run(
            ["rsvg-convert", "-w", str(w), "-h", str(h), SVG,
             "-o", os.path.join(out, "launcher_icon.png")],
            check=True,
        )
        with open(os.path.join(out, "drawables.xml"), "w") as f:
            f.write(DRAWABLES_XML)

    subprocess.run(
        ["rsvg-convert", "-w", "40", "-h", "40", SVG,
         "-o", os.path.join(ROOT, "resources", "drawables", "launcher_icon.png")],
        check=True,
    )

    print(f"rendered {len(sizes)} sizes + fallback")
    return 0


if __name__ == "__main__":
    sys.exit(main())
