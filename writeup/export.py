# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Regenerate the Markdown copy and standalone SVG diagrams from agent-memory-proof.html.

Usage: uv run export.py

Reads agent-memory-proof.html next to this script, which is the source of truth, and writes:
  agent-memory-proof.md     the same content as Markdown, one line per paragraph
  diagrams/*.svg            each inline diagram as a standalone SVG with its own light and dark styles
Fails if any evidence link in the page points at a missing file in the stage folders.
"""
import html
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
src = (HERE / "agent-memory-proof.html").read_text()

# 1. Every evidence link must resolve to a file in the stage folders.
for href in re.findall(r'href="(\.\./[^"]+)"', src):
    if not (HERE / href).exists():
        sys.exit(f"missing local file for link: {href}")

# 2. Standalone SVG diagrams with the page's diagram styles inlined.
SVG_STYLE = """<style>
  :root { --fg: #14232b; --muted: #55666f; --bg: #f6f8f9; --panel: #eaf0f2; --panel-line: #b9c7cd; --accent: #0a6f86; --accent-soft: #d6ecf1; }
  @media (prefers-color-scheme: dark) { :root { --fg: #e3ecef; --muted: #93a6ae; --bg: #0c1519; --panel: #13232a; --panel-line: #34505a; --accent: #4fc3dc; --accent-soft: #0f2f38; } }
  svg { color: var(--fg); background: var(--bg); }
  text { fill: currentColor; font: 12px "Public Sans", "Helvetica Neue", Arial, sans-serif; }
  .mono { font-family: "JetBrains Mono", Menlo, monospace; font-size: 11.5px; }
  .t { font-weight: 600; font-size: 13px; } .sm { font-size: 11px; }
  .mut { fill: var(--muted); } .acct { fill: var(--accent); }
  .box { fill: var(--panel); stroke: var(--panel-line); } .plain { fill: var(--bg); stroke: var(--panel-line); }
  .accbox { fill: var(--accent-soft); stroke: var(--accent); } .frame { fill: none; stroke: var(--muted); stroke-dasharray: 5 4; }
  .ln { fill: none; stroke: currentColor; stroke-width: 1.3; } .ret { stroke-dasharray: 5 4; } .acc { stroke: var(--accent); stroke-width: 1.8; }
  .life { stroke: var(--muted); stroke-dasharray: 2 4; } .band { fill: var(--panel); opacity: 0.55; }
  .halo { paint-order: stroke; stroke: var(--bg); stroke-width: 4px; stroke-linejoin: round; }
  .mk { fill: currentColor; } .mkacc { fill: var(--accent); }
</style>"""
NAMES = {"Agent loop": "agent-loop", "Actor model": "actor-model", "Schema": "schema", "Architecture": "architecture", "Call flow": "call-flow-ladder"}
(HERE / "diagrams").mkdir(exist_ok=True)
svg_files = {}
for n, svg in enumerate(re.findall(r'<svg class="diag".*?</svg>', src, re.S), start=1):
    label = re.search(r'aria-label="([^"]+)"', svg).group(1)
    key = next(k for k in NAMES if label.startswith(k))
    fname = f"diagrams/{n:02d}-{NAMES[key]}.svg"
    vb = re.search(r'viewBox="0 0 (\d+) (\d+)"', svg)
    out = svg.replace('<svg class="diag"', f'<svg xmlns="http://www.w3.org/2000/svg" width="{vb.group(1)}" height="{vb.group(2)}"', 1)
    out = out.replace("</defs>", "</defs>\n" + SVG_STYLE, 1)
    out = out.replace('style="stroke: var(--panel-line)"', 'stroke="#b9c7cd"')
    (HERE / fname).write_text(out + "\n")
    svg_files[n] = (fname, label)

# 3. Markdown.
main = src[src.index("<main>") + 6:src.index("</main>")]


def inline(s):
    s = re.sub(r"<code>(.*?)</code>", lambda m: "`" + html.unescape(re.sub(r"<[^>]+>", "", m.group(1))) + "`", s, flags=re.S)
    s = re.sub(r"<strong>(.*?)</strong>", r"**\1**", s, flags=re.S)
    s = re.sub(r'<a href="([^"]+)">(.*?)</a>', r"[\2](\1)", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip()


def table(t):
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", t, re.S)
    cells = [[inline(c) for c in re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", r, re.S)] for r in rows]
    right = [("class=\"n" in c) for c in re.findall(r"<th[^>]*>", rows[0])]
    lines = ["| " + " | ".join(cells[0]) + " |", "| " + " | ".join("---:" if r else "---" for r in right) + " |"]
    lines += ["| " + " | ".join(c.replace("|", "\\|") for c in row) + " |" for row in cells[1:]]
    return "\n".join(lines)


def term(t):
    head = inline(re.search(r'<div class="term-head"><span>(.*?)</span>', t, re.S).group(1))
    body = re.search(r"<pre[^>]*>(.*?)</pre>", t, re.S).group(1)
    body = html.unescape(re.sub(r"<[^>]+>", "", body))
    lang = "sql" if ("SELECT" in body or "CREATE" in body) and not body.startswith("+") and "docker" not in body else ("bash" if "docker" in body else "text")
    return f"{head}:\n\n```{lang}\n{body.rstrip()}\n```"


md, fig_n, eyebrow, in_log = [], 0, None, False
title = re.search(r"<title>(.*?)</title>", src).group(1)
tokens = re.finditer(
    r'(?P<fig><figure class="fig">.*?</figure>)|(?P<term><div class="term">.*?</pre>\s*</div>)|(?P<tbl><div class="tablewrap">.*?</table>\s*</div>)'
    r'|<div class="eyebrow">(?P<eyebrow>.*?)</div>|<h1>(?P<h1>.*?)</h1>|<h2>(?P<h2>.*?)</h2>|<h3>(?P<h3>.*?)</h3>'
    r'|<span class="pill [a-z]+">(?P<pill>.*?)</span>|<div class="group">(?P<group>.*?)</div>|<span class="num">(?P<num>\d+)</span>'
    r'|<p class="lede">(?P<lede>.*?)</p>|<p class="tag">(?P<tag>.*?)</p>|<p[^>]*>(?P<p>.*?)</p>|<li>(?P<li>.*?)</li>'
    r'|<div class="ver">(?P<ver>.*?)</div>|<div class="files">(?P<files>.*?)</div>|<footer>(?P<footer>.*?)</footer>',
    main, re.S)
pending_num = None
for m in tokens:
    k = m.lastgroup
    v = m.group(k)
    if k == "fig":
        fig_n += 1
        fname, label = svg_files[fig_n]
        cap = inline(re.search(r"<figcaption>(.*?)</figcaption>", v, re.S).group(1))
        md += [f"![{label}]({fname})", f"*{cap}*"]
    elif k == "term":
        md.append(term(v))
    elif k == "tbl":
        md.append(table(v))
    elif k == "eyebrow":
        eyebrow = inline(v)
    elif k == "h1":
        md += [f"# {inline(v)}", f"Positioning: {eyebrow}"]
        eyebrow = None
    elif k == "h2":
        h = inline(v)
        if eyebrow and eyebrow.startswith(("Step", "Appendix")):
            h = f"{eyebrow.split(' · ')[0]} · {h}"
        in_log = bool(eyebrow and eyebrow.startswith("Appendix"))
        md.append(f"## {h}")
        eyebrow = None
    elif k == "h3":
        h = inline(v)
        md.append(f"#### {pending_num}. {h}" if pending_num else f"### {h}")
        pending_num = None
    elif k == "num":
        pending_num = v
    elif k == "pill":
        md.append(f"Status: {inline(v)}")
    elif k == "group":
        md.append(f"### {inline(v)}")
    elif k in ("lede", "p"):
        md.append(inline(v))
    elif k == "tag":
        md.append(f"> {inline(v)}")
    elif k == "li":
        md.append("- " + inline(v))
    elif k == "ver":
        md.append("- " + inline(v))
    elif k == "files":
        md.append("\n".join(f"- [{inline(t)}]({h})" for h, t in re.findall(r'<a href="([^"]+)">(.*?)</a>', v)))
    elif k == "footer":
        md.append(f"*{inline(v)}*")

# Join, keeping list items together and everything else separated by one blank line.
out = []
for block in md:
    if out and block.startswith("- ") and out[-1].startswith("- "):
        out[-1] += "\n" + block
    else:
        out.append(block)
text = "\n\n".join(out) + "\n"
text = text.replace(f"# {title}", f"# {title}", 1)
(HERE / "agent-memory-proof.md").write_text(text)
print("wrote md,", len(svg_files), "svg")
