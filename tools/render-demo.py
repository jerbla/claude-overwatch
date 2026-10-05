#!/usr/bin/env python3
"""Render docs/demo.gif from a real ./overwatch session recording.

Record the viewer with util-linux `script` while Claude works, e.g.
  script -q -f -c "stty cols 100 rows 34; zsh .vscode/claude-live.zsh" -T timing typescript
then: python3 tools/render-demo.py typescript timing docs/demo.gif
Nothing is added or invented: the frames are the viewer's own terminal output, replayed with
its real timing through a tiny terminal emulator (colors, cursor-left, clear, wrap, scroll).
"""
import re, sys
from PIL import Image, ImageDraw, ImageFont

COLS, ROWS, FPS, HOLD = 100, 34, 10, 3.0
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
FONT_B = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 14)
CW, CH = 8.5, 17
DEFAULT = (0x00, 0xff, 0x41)

def xterm(n):
    if n < 16:
        base = [(0,0,0),(205,0,0),(0,205,0),(205,205,0),(0,0,238),(205,0,205),(0,205,205),(229,229,229),
                (127,127,127),(255,0,0),(0,255,0),(255,255,0),(92,92,255),(255,0,255),(0,255,255),(255,255,255)]
        return base[n]
    if n < 232:
        n -= 16; lv = [0, 95, 135, 175, 215, 255]
        return (lv[n // 36], lv[n // 6 % 6], lv[n % 6])
    g = 8 + (n - 232) * 10; return (g, g, g)

class Term:
    def __init__(s):
        s.grid = [[(" ", DEFAULT, False)] * COLS for _ in range(ROWS)]; s.r = s.c = 0
        s.fg, s.bold = DEFAULT, False
    def clear(s): s.grid = [[(" ", DEFAULT, False)] * COLS for _ in range(ROWS)]
    def nl(s):
        s.r += 1
        if s.r >= ROWS: s.grid.pop(0); s.grid.append([(" ", DEFAULT, False)] * COLS); s.r = ROWS - 1
    def put(s, ch):
        if s.c >= COLS: s.c = 0; s.nl()
        row = list(s.grid[s.r]); row[s.c] = (ch, s.fg, s.bold); s.grid[s.r] = row; s.c += 1
    def sgr(s, params):
        p = [int(x) if x else 0 for x in params.split(";")] if params else [0]; i = 0
        while i < len(p):
            if p[i] == 0: s.fg, s.bold = DEFAULT, False
            elif p[i] == 1: s.bold = True
            elif p[i] == 38 and i + 2 < len(p) and p[i+1] == 5: s.fg = xterm(p[i+2]); i += 2
            elif 30 <= p[i] <= 37: s.fg = xterm(p[i] - 30)
            i += 1
    def feed(s, text):
        i = 0
        while i < len(text):
            ch = text[i]
            if ch == "\x1b":
                m = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", text[i:])
                if m:
                    params, cmd = m.group(1), m.group(2)
                    if cmd == "m": s.sgr(params)
                    elif cmd == "D": s.c = max(0, s.c - int(params or 1))
                    elif cmd == "H": s.r = s.c = 0
                    elif cmd == "J": s.clear()
                    i += len(m.group(0)); continue
            elif ch == "\r": s.c = 0
            elif ch == "\n": s.nl()
            elif ch >= " ": s.put(ch)
            i += 1
    def image(s):
        top = 28
        img = Image.new("RGB", (int(COLS * CW) + 24, int(ROWS * CH) + top + 12), (0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, img.width, top - 1], fill=(40, 40, 40))
        for k, col in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
            d.ellipse([12 + k * 20, 8, 24 + k * 20, 20], fill=col)
        t = "./overwatch"; d.text(((img.width - d.textlength(t, font=FONT)) / 2, 6), t, fill=(200, 200, 200), font=FONT)
        for r, row in enumerate(s.grid):
            for c, (ch, fg, b) in enumerate(row):
                if ch != " ": d.text((12 + c * CW, top + 6 + r * CH), ch, fill=fg, font=FONT_B if b else FONT)
        return img

def main(ts_path, timing_path, out):
    raw = open(ts_path, "rb").read(); raw = raw[raw.index(b"\n") + 1:]   # skip "Script started" line
    chunks, pos, t = [], 0, 0.0
    for line in open(timing_path):
        delay, n = line.split(); t += float(delay); n = int(n)
        chunks.append((t, raw[pos:pos + n])); pos += n
    term, frames, durs, buf, nxt, last = Term(), [], [], b"", 0.0, None
    for when, data in chunks:
        while when > nxt:
            img = term.image(); key = img.tobytes()
            if key == last: durs[-1] += 1000 // FPS
            else: frames.append(img); durs.append(1000 // FPS); last = key
            nxt += 1.0 / FPS
        buf += data
        try: text = buf.decode("utf-8"); buf = b""
        except UnicodeDecodeError: continue
        term.feed(text)
    frames.append(term.image()); durs.append(int(HOLD * 1000))
    pal = [f.convert("P", palette=Image.ADAPTIVE, colors=64) for f in frames]
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=durs, loop=0, optimize=True, disposal=1)
    print(f"{out}: {len(frames)} frames, {sum(durs)/1000:.1f}s")

if __name__ == "__main__":
    main(*sys.argv[1:4])
