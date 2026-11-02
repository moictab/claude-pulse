#!/usr/bin/env python3
"""Render ANSI-colored terminal text as an SVG terminal window, for the README preview.

Reads stdin. A line "---caption" starts a new panel with that caption. Understands the
escape codes the claude-pulse scripts emit: truecolor foreground (38;2;R;G;B), dim (2),
reset (0), and OSC 8 hyperlinks (dropped, keeping the link text).

Usage: python3 docs/ansi2svg.py < output.txt > docs/preview.svg
"""
import re
import sys
from html import escape

FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'DejaVu Sans Mono', monospace"
FONT_SIZE = 14
CHAR_WIDTH = 8.45
LINE_HEIGHT = 22
PAD = 24
CAPTION_HEIGHT = 26
PANEL_GAP = 18
FG = "#d4d4d4"
DIM = "#7d8590"
BG = "#161b22"
WINDOW = "#0d1117"

SGR = re.compile(r"\x1b\[([0-9;]*)m")
OSC8 = re.compile(r"\x1b\]8;;[^\x07]*\x07")


def spans(line):
    """Split a line into (text, color) pieces."""
    line = OSC8.sub("", line)
    color, dim, pos = None, False, 0
    for match in SGR.finditer(line):
        if match.start() > pos:
            yield line[pos:match.start()], DIM if dim and not color else (color or FG)
        params = match.group(1)
        if params in ("", "0"):
            color, dim = None, False
        elif params == "2":
            dim = True
        elif params.startswith("38;2;"):
            r, g, b = (int(x) for x in params.split(";")[2:5])
            color = f"#{r:02x}{g:02x}{b:02x}"
        pos = match.end()
    if pos < len(line):
        yield line[pos:], DIM if dim and not color else (color or FG)


def visible_length(line):
    return len(SGR.sub("", OSC8.sub("", line)))


def main():
    panels = []
    for raw in sys.stdin.buffer.read().decode("utf-8").splitlines():
        if raw.startswith("---"):
            panels.append((raw[3:], []))
        elif panels:
            panels[-1][1].append(raw)

    width = PAD * 2 + CHAR_WIDTH * max(visible_length(l) for _, lines in panels for l in lines)
    height = PAD + sum(CAPTION_HEIGHT + LINE_HEIGHT * len(lines) + PANEL_GAP for _, lines in panels) + PAD - PANEL_GAP
    width, height = round(width), round(height)

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
        f'role="img" aria-label="claude-pulse status line and agent panel">',
        f'<rect width="{width}" height="{height}" rx="10" fill="{WINDOW}"/>',
        f'<g font-family="{escape(FONT)}" font-size="{FONT_SIZE}">',
    ]
    y = PAD
    for caption, lines in panels:
        out.append(f'<text x="{PAD}" y="{y + 14}" font-size="12" fill="{DIM}">{escape(caption)}</text>')
        y += CAPTION_HEIGHT
        box_height = LINE_HEIGHT * len(lines) + 8
        out.append(f'<rect x="{PAD - 10}" y="{y - 6}" width="{width - 2 * PAD + 20}" height="{box_height}" rx="6" fill="{BG}"/>')
        for line in lines:
            pieces = "".join(f'<tspan fill="{color}">{escape(text)}</tspan>' for text, color in spans(line))
            out.append(f'<text x="{PAD}" y="{y + 14}" xml:space="preserve">{pieces}</text>')
            y += LINE_HEIGHT
        y += PANEL_GAP
    out += ["</g>", "</svg>", ""]
    sys.stdout.buffer.write("\n".join(out).encode("utf-8"))


if __name__ == "__main__":
    main()
