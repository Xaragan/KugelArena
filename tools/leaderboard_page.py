"""Builds training/leaderboard.html from training/leaderboard.json (standard library only).

    python tools/leaderboard_page.py

Run training/leaderboard.gd first; it writes the JSON.
"""
import html
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = json.load(open(os.path.join(ROOT, "training", "leaderboard.json"), encoding="utf-8"))
extra_path = os.path.join(ROOT, "training", "leaderboard_extra.json")
extra = json.load(open(extra_path, encoding="utf-8")) if os.path.exists(extra_path) else {}

nets = [n for n in data["nets"] if n["score"] >= 0]
runs = [r for r in data["runs"] if r["tests"]]


def pct(x):
    return f"{100 * x:.1f}"


def chart(run):
    tests = run["tests"]
    w, h, left, right, top, bottom = 760, 300, 44, 96, 16, 34
    max_g = max(t["generation"] for t in tests) or 1
    px = lambda g: left + (w - left - right) * g / max_g
    py = lambda v: top + (h - top - bottom) * (1 - v)
    out = [f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="Win rates of run {html.escape(run["run"])} over the generations">']
    for v in (0, 0.25, 0.5, 0.75, 1.0):
        out.append(f'<line x1="{left}" x2="{w - right}" y1="{py(v):.1f}" y2="{py(v):.1f}" class="grid"/>')
        out.append(f'<text x="{left - 8}" y="{py(v) + 4:.1f}" class="tick" text-anchor="end">{int(v * 100)}</text>')
    step = max(10, int(round(max_g / 8 / 10)) * 10)
    for g in range(0, max_g + 1, step):
        out.append(f'<text x="{px(g):.1f}" y="{h - 12}" class="tick" text-anchor="middle">{g}</text>')
    out.append(f'<text x="{w - right}" y="{h - 12}" class="tick" text-anchor="end" dx="-4" dy="-14">generation</text>')
    out.append(f'<line x1="{left}" x2="{w - right}" y1="{py(0.25):.1f}" y2="{py(0.25):.1f}" class="chance"/>')
    out.append(f'<text x="{w - right + 8}" y="{py(0.25) + 4:.1f}" class="lab chance-lab">chance in FFA</text>')
    for key, cls, name in (("duel", "duel", "Duel"), ("ffa", "ffa", "Free-for-all")):
        pts = " ".join(f"{px(t['generation']):.1f},{py(t[key]):.1f}" for t in tests)
        out.append(f'<polyline points="{pts}" class="line {cls}" fill="none"/>')
        last = tests[-1]
        out.append(f'<circle cx="{px(last["generation"]):.1f}" cy="{py(last[key]):.1f}" r="4" class="dot {cls}"/>')
        out.append(f'<text x="{w - right + 8}" y="{py(last[key]) + 4:.1f}" class="lab {cls}-lab">{name} {pct(last[key])}</text>')
    out.append("</svg>")
    return "\n".join(out)


def bar(value, cls):
    return (f'<div class="bar"><span class="fill {cls}" style="width:{max(0.0, min(1.0, value)) * 100:.1f}%"></span>'
            f'<b>{pct(value)}</b></div>')


rows = []
for i, n in enumerate(nets):
    kept = '<span class="kept" title="Was the best net of its run when it was tested">kept</span>' if n["kept"] else ""
    rows.append(
        f'<tr><td class="num">{i + 1}</td>'
        f'<td><strong>{html.escape(n["name"])}</strong> {kept}<small>{html.escape(n["plays"])}</small></td>'
        f'<td class="num">{n["generation"]}</td><td class="num">{n["minutes"]:.1f}</td>'
        f'<td>{bar(n["duel"], "duel")}</td><td>{bar(n["ffa"], "ffa")}</td>'
        f'<td class="num score">{pct(n["score"])}</td></tr>')

best = nets[0] if nets else None
summary = ""
if best:
    summary = (f'<p class="lead">Best net right now: <strong>{html.escape(best["name"])}</strong>, age {best["generation"]}, '
               f'after {best["minutes"]:.1f} minutes of training. Against the scripted bots it wins '
               f'<strong>{pct(best["duel"])} %</strong> of duels and <strong>{pct(best["ffa"])} %</strong> of '
               f'four-ball free-for-alls, where winning by chance would be 25 %.</p>')

fresh = ""
if extra.get("fresh"):
    items = "".join(f'<li><b>{html.escape(str(v))}</b><span>{html.escape(k)}</span></li>' for k, v in extra["fresh"].items())
    fresh = (f'<section><h2>Measured on fresh games</h2><p class="note">{html.escape(extra.get("fresh_note", ""))}</p>'
             f'<ul class="facts">{items}</ul></section>')
tournament = ""
if extra.get("tournament_html"):
    tournament = f'<section><h2>Everyone against everyone</h2>{extra["tournament_html"]}</section>'

charts = "".join(
    f'<section><h2>How run "{html.escape(r["run"])}" learned</h2>'
    f'<p class="note">Win rate in the test games after every 10 generations (per cent). '
    f'The net of this run is called {html.escape(r["first_name"])}; its age is the generation.</p>'
    f'<div class="chart">{chart(r)}</div></section>' for r in runs)

page = f"""<title>KugelArena Leaderboard</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;700&display=swap">
<style>
/* Layout: one column, the game's own night-blue disc palette; blue = duel, red = free-for-all, as the two balls in a duel. */
:root {{
  color-scheme: dark;
  --bg: #0d0f1a; --panel: #161a28; --line: #2a3046; --fg: #e1e5f4; --dim: #8c95b3;
  --duel: #4d9eff; --ffa: #ff6652; --gold: #ffc733;
  --display: "Space Grotesk", "Segoe UI", system-ui, sans-serif;
  --body: Inter, "Segoe UI", system-ui, sans-serif;
}}
body {{ background: var(--bg); color: var(--fg); font-family: var(--body); font-size: 15px; line-height: 1.55;
  padding-block: 32px 56px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }}
main {{ max-width: 920px; margin: 0 auto; display: flex; flex-direction: column; gap: 36px; }}
h1 {{ font-family: var(--display); font-size: 2.1rem; line-height: 1.1; margin: 0; text-wrap: balance; }}
h2 {{ font-family: var(--display); font-size: 1.2rem; margin: 0 0 6px; text-wrap: balance; }}
header p, .note {{ color: var(--dim); margin: 6px 0 0; max-width: 65ch; }}
.lead {{ font-size: 1.05rem; max-width: 65ch; margin: 14px 0 0; color: var(--fg); }}
.chart {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 12px; margin-top: 12px; overflow-x: auto; }}
svg {{ display: block; width: 100%; min-width: 520px; height: auto; }}
.grid {{ stroke: var(--line); stroke-width: 1; }}
.tick {{ fill: var(--dim); font: 11px var(--body); }}
.lab {{ font: 600 12px var(--body); }}
.line {{ stroke-width: 2.5; stroke-linejoin: round; }}
.line.duel {{ stroke: var(--duel); }} .line.ffa {{ stroke: var(--ffa); }}
.dot.duel {{ fill: var(--duel); }} .dot.ffa {{ fill: var(--ffa); }}
.duel-lab {{ fill: var(--duel); }} .ffa-lab {{ fill: var(--ffa); }}
.chance {{ stroke: var(--dim); stroke-width: 1; stroke-dasharray: 4 4; }} .chance-lab {{ fill: var(--dim); font-weight: 400; }}
.table {{ overflow-x: auto; margin-top: 12px; }}
table {{ border-collapse: collapse; width: 100%; min-width: 640px; font-variant-numeric: tabular-nums; }}
th {{ text-align: left; font: 500 11px var(--body); letter-spacing: .06em; text-transform: uppercase; color: var(--dim); padding: 0 10px 8px; }}
td {{ padding: 9px 10px; border-top: 1px solid var(--line); vertical-align: middle; }}
td small {{ display: block; color: var(--dim); font-size: 12px; }}
.num {{ text-align: right; }} th.num {{ text-align: right; }}
.score {{ font-family: var(--display); font-weight: 700; color: var(--gold); }}
.bar {{ position: relative; background: var(--panel); border-radius: 4px; height: 22px; min-width: 110px; }}
.bar .fill {{ position: absolute; inset: 0 auto 0 0; border-radius: 4px; opacity: .55; }}
.fill.duel {{ background: var(--duel); }} .fill.ffa {{ background: var(--ffa); }}
.bar b {{ position: relative; font-weight: 600; font-size: 13px; line-height: 22px; padding-left: 8px; }}
.kept {{ font-size: 11px; color: var(--gold); border: 1px solid var(--gold); border-radius: 99px; padding: 0 7px; margin-left: 6px; }}
.facts {{ list-style: none; padding: 0; margin: 12px 0 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 12px; }}
.facts li {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; }}
.facts b {{ display: block; font: 700 1.5rem var(--display); }} .facts span {{ color: var(--dim); font-size: 13px; }}
.tour {{ overflow-x: auto; }} .tour table {{ min-width: 520px; }}
</style>
<main>
<header>
  <h1>KugelArena Leaderboard</h1>
  <p>Every saved net, best first. Written {html.escape(data["written"])}.</p>
  {summary}
</header>
{fresh}
{charts}
<section>
  <h2>All nets</h2>
  <p class="note">Duel: share of 600 test duels won against four scripted bots. Free-for-all: share of 400
  four-ball rounds in which it was the last ball on the disc, against three of those bots. Score: the mean of
  the two. The same test games every time, so rows compare directly.</p>
  <div class="table"><table>
    <thead><tr><th class="num">#</th><th>Net</th><th class="num">Age</th><th class="num">Minutes</th><th>Duel wins %</th><th>Free-for-all wins %</th><th class="num">Score</th></tr></thead>
    <tbody>{''.join(rows)}</tbody>
  </table></div>
</section>
{tournament}
</main>
"""
out = os.path.join(ROOT, "training", "leaderboard.html")
open(out, "w", encoding="utf-8").write(page)
print("written", out, len(page), "bytes")
