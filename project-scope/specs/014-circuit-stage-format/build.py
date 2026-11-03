# -*- coding: utf-8 -*-
import io
from bracket_svg import diagram, MEN, LADIES
import bracket_html as BH

men    = diagram(MEN)
ladies = diagram(LADIES)

def ladder():
    men_boxes = [("64","qualifiers"),("32",""),("16",""),("8","quarter-finalists"),
                 ("4","semi-finalists"),("2","finalists"),("1","CHAMPION")]
    lad_boxes = [("32","qualifiers"),("16",""),("8","quarter-finalists"),
                 ("4","semi-finalists"),("2","finalists"),("1","CHAMPION")]
    xs = [20,165,310,455,600,745,890]
    out = ['<svg viewBox="0 0 1050 250" xmlns="http://www.w3.org/2000/svg" class="flow">',
           '<defs><marker id="lk" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto">'
           '<path d="M0,0 L7,3 L0,6 z" fill="#524b63"/></marker></defs>']

    def row(boxes, offset, y, label, matches):
        out.append(f'<text x="20" y="{y-14}" class="lane">{label}</text>')
        for i,(n,sub) in enumerate(boxes):
            x = xs[i+offset]
            champ = (n == "1")
            fill, stroke = ("#fcefcb","#d9a02b") if champ else ("#ffffff","#dbdbde")
            out.append(f'<rect x="{x}" y="{y}" width="120" height="56" rx="10" fill="{fill}" '
                       f'stroke="{stroke}" stroke-width="{1.5 if champ else 1}"/>')
            out.append(f'<text x="{x+60}" y="{y+28}" class="big" '
                       f'fill="{"#9c7318" if champ else "#16152b"}">{n}</text>')
            if sub:
                out.append(f'<text x="{x+60}" y="{y+45}" class="el" '
                           f'fill="{"#9c7318" if champ else "#6e6d7a"}">{sub}</text>')
        for i,m in enumerate(matches):
            x1 = xs[i+offset]+120; x2 = xs[i+offset+1]
            out.append(f'<path d="M{x1},{y+28} L{x2-8},{y+28}" stroke="#524b63" stroke-width="1.5" '
                       f'fill="none" marker-end="url(#lk)"/>')
            out.append(f'<text x="{(x1+x2)/2}" y="{y+20}" class="el">{m}</text>')

    row(men_boxes, 0, 40, "MEN &#183; 64 qualifiers &#183; race to 5", ["32","16","8","4","2","1"])
    row(lad_boxes, 1, 170, "LADIES &#183; 32 qualifiers &#183; race to 5", ["16","8","4","2","1"])
    out.append('</svg>')
    return "\n".join(out)

HTML = u'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Circuit Stage Format</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root {
    --ink-950:#0d0c22; --ink-900:#16152b; --ink-700:#3a3546; --ink-600:#524b63;
    --ink-500:#6e6d7a; --ink-400:#9e9ea7; --ink-300:#dbdbde; --ink-200:#e7e7e9;
    --ink-100:#f3f3f4; --ink-50:#faf9fb;
    --red-500:#e32219; --red-700:#a81810; --red-50:#fdecea; --red-100:#fbd5d0;
    --green-500:#16a34a; --green-700:#0e6a30; --green-50:#f0faf3;
    --gold-500:#d9a02b; --gold-700:#9c7318; --gold-100:#fcefcb;
  }
  @page { size: A4; margin: 15mm 14mm 16mm; }
  * { box-sizing: border-box; }
  body { font-family: Inter, "Helvetica Neue", Arial, sans-serif; color: var(--ink-900);
         font-size: 9.6pt; line-height: 1.5; margin: 0; }
  h1 { font-size: 21pt; line-height:1.15; margin: 0 0 6px; letter-spacing: -0.02em; }
  h2 { font-size: 12.5pt; margin: 0 0 10px; padding-bottom: 6px;
       border-bottom: 2px solid var(--red-500); letter-spacing: -0.01em; }
  h3 { font-size: 10pt; margin: 16px 0 6px; color: var(--ink-700); }
  p { margin: 0 0 9px; }
  section { page-break-inside: avoid; margin-bottom: 20px; }
  .page-break { page-break-before: always; }
  .keep { page-break-inside: avoid; }
  .cover { border-left: 4px solid var(--red-500); padding-left: 14px; margin-bottom: 22px; }
  .sub { color: var(--ink-500); font-size: 10pt; margin: 0; }
  .meta { color: var(--ink-400); font-size: 8pt; margin-top: 8px; text-transform: uppercase;
          letter-spacing: 0.06em; }
  table { width: 100%; border-collapse: collapse; margin: 8px 0 10px; font-size: 8.8pt; }
  th { text-align: left; font-weight: 600; font-size: 7.6pt; text-transform: uppercase;
       letter-spacing: 0.05em; color: var(--ink-500); border-bottom: 1px solid var(--ink-300);
       padding: 5px 7px; }
  td { padding: 5px 7px; border-bottom: 1px solid var(--ink-200); vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  tbody tr:nth-child(even) { background: var(--ink-50); }
  tfoot td { font-weight: 600; border-top: 1.5px solid var(--ink-300); background: var(--ink-100); }
  ul, ol { margin: 0 0 9px; padding-left: 17px; }
  li { margin-bottom: 4px; }
  .cards { display: flex; gap: 8px; margin-bottom: 14px; }
  .card { flex: 1; border: 1px solid var(--ink-200); border-radius: 10px; padding: 9px 11px;
          background: #fff; }
  .card .k { font-size: 7.2pt; text-transform: uppercase; letter-spacing: 0.06em;
             color: var(--ink-500); margin-bottom: 3px; }
  .card .v { font-size: 15pt; font-weight: 700; line-height: 1.1; letter-spacing: -0.02em; }
  .card .d { font-size: 7.6pt; color: var(--ink-500); margin-top: 2px; }
  .flow { width: 100%; height: auto; display: block; margin: 6px 0 4px; }
  /* --- CueVerse prototype bracket grammar (screens/P-Bracket.dc.html) --- */
  .brk { font-family: Figtree, Inter, system-ui, sans-serif; margin: 4px 0 2px;
         transform-origin: top left; }
  .brk .col { display: flex; flex-direction: column; justify-content: space-around; }
  .brk .m { position: relative; height: 46px; border-radius: 8px; display: flex;
            flex-direction: column; color: #141818; font-size: 11px; line-height: 15px;
            flex: none; }
  .brk .mr { height: 22px; display: flex; align-items: center; gap: 6px; padding: 0 8px; }
  .brk .nm { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
             font-weight: inherit; }
  .brk .scr { font-weight: 700; font-variant-numeric: tabular-nums; min-width: 12px;
              text-align: right; }
  .brk .seed { width: 14px; color: #696d6c; font-variant-numeric: tabular-nums;
               font-size: 10px; }
  .brk .ov { font-size: 9px; line-height: 12px; font-weight: 600; letter-spacing: .06em;
             text-transform: uppercase; color: #696d6c; }
  .lane { font-size: 10px; font-weight: 600; fill: var(--ink-500);
          text-transform: uppercase; letter-spacing: 0.07em; }
  .lane.muted { fill: var(--ink-400); }
  .nt { font-size: 12px; font-weight: 700; fill: var(--ink-900); text-anchor: middle; }
  .nn { font-size: 15px; font-weight: 700; fill: var(--ink-900); text-anchor: middle; }
  .ns { font-size: 10px; fill: var(--ink-500); text-anchor: middle; }
  .ns.muted { fill: var(--ink-400); }
  .el { font-size: 9.5px; font-weight: 600; fill: var(--ink-600); text-anchor: middle; }
  .big { font-size: 19px; font-weight: 700; text-anchor: middle; }
  .xl { font-size: 30px; font-weight: 700; text-anchor: middle; }
  .note { border-left: 3px solid var(--gold-500); background: #fffdf6; padding: 8px 11px;
          border-radius: 0 8px 8px 0; margin: 10px 0; font-size: 8.8pt; }
  .note .t { font-weight: 700; color: var(--gold-700); display:block; margin-bottom: 2px; }
  .warn { border-left: 3px solid var(--red-500); background: var(--red-50); padding: 8px 11px;
          border-radius: 0 8px 8px 0; margin: 10px 0; font-size: 8.8pt; }
  .warn .t { font-weight: 700; color: var(--red-700); display:block; margin-bottom: 2px; }
  .cap { font-size: 7.8pt; color: var(--ink-400); margin: 2px 0 0; }
  .q { counter-reset: none; }
  .q li { margin-bottom: 7px; }
  .q b { color: var(--ink-950); }
  code { font-family: "IBM Plex Mono", Menlo, monospace; font-size: 8.2pt;
         background: var(--ink-100); padding: 1px 4px; border-radius: 4px; }
  footer { margin-top: 18px; padding-top: 8px; border-top: 1px solid var(--ink-200);
           font-size: 7.6pt; color: var(--ink-400); }
</style></head><body>

<div class="cover">
  <h1>Circuit Stage &#8212; Competition Format</h1>
  <p class="sub">Men's and Ladies' singles &#183; Circuits 1, 2 and 3 &#183; SportPesa National Pool Circuit 2026/27</p>
  <p class="meta">Draft v1 for committee review &#183; 2 November 2026</p>
</div>

<section>
<h2>At a glance</h2>
<div class="cards">
  <div class="card"><div class="k">Men's field</div><div class="v">128</div>
    <div class="d">full bracket, no byes</div></div>
  <div class="card"><div class="k">Ladies' field</div><div class="v">55</div>
    <div class="d">64 slots, 9 byes</div></div>
  <div class="card"><div class="k">Round 1</div><div class="v">Double</div>
    <div class="d">elimination &#183; race to 6</div></div>
  <div class="card"><div class="k">Round 2</div><div class="v">Knockout</div>
    <div class="d">straight &#183; race to 5</div></div>
  <div class="card"><div class="k">Outcome</div><div class="v">1 + 1</div>
    <div class="d">champion per category</div></div>
</div>
<p>Each circuit is a self-contained competition. Round 1 is a double-elimination phase that
halves the field: a player must lose <b>twice</b> to go out. Everyone who survives Round 1 enters
Round 2 with a clean sheet, and from there a single loss ends the run &#8212; straight knockout
down to a champion.</p>
<table>
  <thead><tr><th>&nbsp;</th><th class="num">Men</th><th class="num">Ladies</th></tr></thead>
  <tbody>
    <tr><td>Entrants</td><td class="num">128</td><td class="num">55</td></tr>
    <tr><td>Bracket slots</td><td class="num">128</td><td class="num">64</td></tr>
    <tr><td>Byes in Round 1</td><td class="num">0</td><td class="num">9</td></tr>
    <tr><td>Eliminated in Round 1</td><td class="num">64</td><td class="num">23</td></tr>
    <tr><td>Qualify for Round 2</td><td class="num">64</td><td class="num">32</td></tr>
    <tr><td>Matches played, Round 1</td><td class="num">160</td><td class="num">62</td></tr>
    <tr><td>Matches played, Round 2</td><td class="num">63</td><td class="num">31</td></tr>
  </tbody>
  <tfoot><tr><td>Total matches per circuit</td><td class="num">223</td><td class="num">93</td></tr></tfoot>
</table>
<p class="cap">Ladies' Round 1 total excludes 9 byes and 9 losers&#8217;-bracket walkovers, which are
awarded rather than played.</p>
</section>

<section>
<h2>Round 1 &#8212; double elimination, race to 6</h2>
<p>Round 1 runs as four waves of matches. The winners&#8217; side and the losers&#8217; side both
play, and the two sides meet once, in the crossover, before the round closes.</p>
<table>
  <thead><tr><th>Wave</th><th>Who plays</th><th class="num">Players</th><th class="num">Matches</th>
    <th>Winners go to</th><th>Losers go to</th></tr></thead>
  <tbody>
    <tr><td><b>WB R1</b></td><td>The whole field</td><td class="num">128</td><td class="num">64</td>
      <td>Winners&#8217; bracket R2</td><td>Losers&#8217; bracket R1</td></tr>
    <tr><td><b>WB R2</b></td><td>The 64 unbeaten</td><td class="num">64</td><td class="num">32</td>
      <td><b>Round 2</b> (undefeated)</td><td>Losers&#8217; bracket R2</td></tr>
    <tr><td><b>LB R1</b></td><td>The 64 first-round losers</td><td class="num">64</td><td class="num">32</td>
      <td>Losers&#8217; bracket R2</td><td>Eliminated &#8212; 2 losses</td></tr>
    <tr><td><b>LB R2</b></td><td>32 WB R2 losers v 32 LB R1 winners</td><td class="num">64</td>
      <td class="num">32</td><td><b>Round 2</b> (one loss)</td><td>Eliminated &#8212; 2 losses</td></tr>
  </tbody>
  <tfoot><tr><td colspan="3">Round 1 total</td><td class="num">160</td>
    <td colspan="2">64 through, 64 out</td></tr></tfoot>
</table>
<p>Every Round 1 match is a <b>race to 6</b>. The crossover (LB R2) is the match that makes this a
true double elimination: a player who lost their opening match can still reach Round 2 by winning
two matches on the losers&#8217; side.</p>
</section>

<section class="page-break">
<h2>Round 1 bracket &#8212; the format shown at 16 players</h2>
<p>The same bracket as the 128 and 64 draws, scaled down so every match fits on a page:
16 players, 8 through to Round 2. Each card is one match &#8212; winner in black, beaten player in
grey. The real draws are this shape multiplied.</p>

<div class="keep"><h3>Winners&#8217; side &#8212; nobody here has lost</h3>
__WINNERS__
<p class="cap">The 8 players beaten in WB Round 1 drop to the losers&#8217; side below. The 4 beaten
in WB Round 2 drop straight into the crossover.</p></div>

<div class="keep"><h3>Losers&#8217; side &#8212; one more loss and you are out</h3>
__LOSERS__
<p class="cap">In each crossover card the top name is the player who has just dropped from WB Round 2
and the bottom name is the LB Round 1 winner. Daniel Kariuki, Mercy Atieno, Diana Muthoni and Ivy
Akinyi went out in LB Round 1; Tom Gitau, Lucy Chebet, Faith Njeri and Collins Ouma went out in the
crossover &#8212; eight players, two losses each.</p></div>

<div class="keep"><h3>Round 2 &#8212; the 4 undefeated meet the 4 survivors</h3>
__ROUND2__
<p class="cap">Dashed cards are not yet drawn. Every opening Round 2 match is undefeated versus
survivor, never two undefeated players against each other.</p></div>

<table style="margin-top:12px">
  <thead><tr><th>Wave</th><th class="num">Shown here</th><th class="num">Men's draw</th>
    <th class="num">Ladies' draw</th></tr></thead>
  <tbody>
    <tr><td>Field</td><td class="num">16</td><td class="num">128</td><td class="num">55 in 64</td></tr>
    <tr><td>WB Round 1 matches</td><td class="num">8</td><td class="num">64</td><td class="num">23 + 9 byes</td></tr>
    <tr><td>WB Round 2 matches</td><td class="num">4</td><td class="num">32</td><td class="num">16</td></tr>
    <tr><td>LB Round 1 matches</td><td class="num">4</td><td class="num">32</td><td class="num">7 + 9 w/o</td></tr>
    <tr><td>Crossover matches</td><td class="num">4</td><td class="num">32</td><td class="num">16</td></tr>
  </tbody>
  <tfoot><tr><td>Through to Round 2</td><td class="num">8</td><td class="num">64</td><td class="num">32</td></tr></tfoot>
</table>
</section>

<section class="page-break">
<h2>Round 1 flow &#8212; men's 128 bracket</h2>
__MEN__
<p class="cap">Green = unbeaten. Amber = alive on one loss. Dashed grey = out on two losses.
Each box shows the players entering that wave.</p>
</section>

<section>
<h2>Round 1 flow &#8212; ladies' 64 bracket</h2>
__LADIES__
<p class="cap">Same shape, different arithmetic. The 9 byes sit in WB Round 1 and produce no losers, so
the losers&#8217; side carries 23 players through 32 slots &#8212; hence the 9 walkovers in LB Round 1.</p>
</section>

<section>
<h2>The ladies&#8217; field: 55 players in a 64 bracket</h2>
<p>55 entrants are drawn into a 64-slot bracket, leaving <b>9 byes</b>. Byes are assigned by
<b>random draw</b> among all 55, with one structural constraint described below.</p>
<table>
  <thead><tr><th>Wave</th><th class="num">Players in</th><th class="num">Played</th>
    <th class="num">Awarded</th><th class="num">Advance</th><th class="num">Out</th></tr></thead>
  <tbody>
    <tr><td><b>WB R1</b></td><td class="num">55</td><td class="num">23</td><td class="num">9 byes</td>
      <td class="num">32</td><td class="num">0</td></tr>
    <tr><td><b>WB R2</b></td><td class="num">32</td><td class="num">16</td><td class="num">0</td>
      <td class="num">16</td><td class="num">0</td></tr>
    <tr><td><b>LB R1</b></td><td class="num">23</td><td class="num">7</td><td class="num">9 w/o</td>
      <td class="num">16</td><td class="num">7</td></tr>
    <tr><td><b>LB R2</b></td><td class="num">32</td><td class="num">16</td><td class="num">0</td>
      <td class="num">16</td><td class="num">16</td></tr>
  </tbody>
  <tfoot><tr><td>Round 1</td><td class="num">55</td><td class="num">62</td><td class="num">18</td>
    <td class="num">32</td><td class="num">23</td></tr></tfoot>
</table>
<div class="warn"><span class="t">Draw constraint &#8212; two byes must never feed the same losers&#8217; match</span>
Each losers&#8217;-bracket R1 match is fed by the losers of two specific winners&#8217;-bracket R1
matches. A bye produces no loser, so it leaves that feeder slot empty. If <b>both</b> feeders of one
losers&#8217; match are byes, that match has no players at all and the losers&#8217; side delivers
only 15 players into the crossover &#8212; which needs exactly 16. The draw must therefore place at
most one bye per losers&#8217;-bracket pairing. With 9 byes across 16 pairings this is always
satisfiable, but it has to be enforced when the draw is made, not checked afterwards.</div>
<div class="note"><span class="t">Why 9 and not some other number</span>
The bye count is whatever brings the field up to the next power of two: 64 &#8722; 55 = 9. If entries
change at Circuits 2 and 3, the bye count changes with them. Below 33 entrants the bracket should
drop to 32 slots rather than carry 30-plus byes.</div>
</section>

<section>
<h2>Round 2 &#8212; straight knockout to a champion, race to 5</h2>
<p>Round 2 opens with the 32 undefeated players meeting the 32 one-loss survivors. From that point
the competition is a conventional single-elimination ladder: lose once and you are out, regardless
of how you arrived.</p>
__LADDER__
<p>Records from Round 1 do not carry forward &#8212; a player who arrives with one loss is on equal
footing with an undefeated player. The only advantage of arriving undefeated is in the pairing: the
opening Round 2 match is always <b>undefeated versus one-loss survivor</b>, never two undefeated
players against each other.</p>
<table>
  <thead><tr><th>Stage</th><th class="num">Men in</th><th class="num">Matches</th>
    <th class="num">Ladies in</th><th class="num">Matches</th></tr></thead>
  <tbody>
    <tr><td>Round of 64</td><td class="num">64</td><td class="num">32</td>
      <td class="num">&#8212;</td><td class="num">&#8212;</td></tr>
    <tr><td>Round of 32</td><td class="num">32</td><td class="num">16</td>
      <td class="num">32</td><td class="num">16</td></tr>
    <tr><td>Round of 16</td><td class="num">16</td><td class="num">8</td>
      <td class="num">16</td><td class="num">8</td></tr>
    <tr><td>Quarter-finals</td><td class="num">8</td><td class="num">4</td>
      <td class="num">8</td><td class="num">4</td></tr>
    <tr><td>Semi-finals</td><td class="num">4</td><td class="num">2</td>
      <td class="num">4</td><td class="num">2</td></tr>
    <tr><td>Final</td><td class="num">2</td><td class="num">1</td>
      <td class="num">2</td><td class="num">1</td></tr>
  </tbody>
  <tfoot><tr><td>Round 2 total</td><td class="num">&#8212;</td><td class="num">63</td>
    <td class="num">&#8212;</td><td class="num">31</td></tr></tfoot>
</table>
</section>

<section>
<h2>Match volume and session planning</h2>
<p><b>316 matches</b> per circuit across both categories &#8212; 223 men's and 93 ladies&#8217;.
The table below converts that into table-hours. It assumes an average of 45 minutes per match and
<b>no</b> idle time between matches, so treat it as a floor, not a forecast.</p>
<table>
  <thead><tr><th class="num">Tables</th><th class="num">Total table-hours</th>
    <th class="num">Hours per day over 3 days</th><th>Comment</th></tr></thead>
  <tbody>
    <tr><td class="num">8</td><td class="num">29.6</td><td class="num">9.9</td>
      <td>Long days; little slack for overruns</td></tr>
    <tr><td class="num">10</td><td class="num">23.7</td><td class="num">7.9</td>
      <td>Workable with a disciplined schedule</td></tr>
    <tr><td class="num">12</td><td class="num">19.8</td><td class="num">6.6</td>
      <td>Comfortable</td></tr>
    <tr><td class="num">16</td><td class="num">14.8</td><td class="num">4.9</td>
      <td>Room for delays and feature-table matches</td></tr>
  </tbody>
</table>
<div class="note"><span class="t">Sequencing constraint</span>
The waves are strictly ordered: LB R1 cannot start until every WB R1 match is finished, and the
crossover needs both WB R2 and LB R1 complete. Those two synchronisation points are where a single
slow match holds up the whole room, so they are worth scheduling around.</div>
</section>

<section>
<h2>Confirmed for this draft</h2>
<ul>
  <li><b>Round 2 runs to a champion</b> in each category &#8212; the circuit is self-contained.</li>
  <li><b>Round 2 is straight knockout</b>, not a continuation of double elimination.</li>
  <li><b>Ladies&#8217; byes are drawn at random</b>, not seeded by ranking or CuevoPoints.</li>
  <li><b>The same format applies to all three circuits</b>; field sizes and bye counts are
      recalculated per circuit from actual entries.</li>
</ul>
</section>

<section>
<h2>Open points for the committee</h2>
<ol class="q">
  <li><b>Race lengths get shorter as the stakes rise.</b> Round 1 is a race to 6 and Round 2 &#8212;
      including quarter-finals, semi-finals and the final &#8212; is a race to 5. This is the
      opposite of the usual pattern. Confirm it is deliberate, or set a longer race for the closing
      stages.</li>
  <li><b>Third-place playoff.</b> The two beaten semi-finalists currently finish joint third.
      Is a playoff wanted, for placings or for prize money?</li>
  <li><b>Round 1 draw rules.</b> Is the opening draw purely random, or are there restrictions such
      as keeping players from the same venue or region apart in early matches?</li>
  <li><b>Round 2 re-draw.</b> Is the undefeated-versus-survivor pairing drawn fresh at the start of
      Round 2, or fixed by bracket position carried over from Round 1?</li>
  <li><b>How the three circuits combine.</b> Each circuit produces a champion. What carries forward
      to the Finals &#8212; circuit champions only, accumulated CuevoPoints, or a ranking across all
      three?</li>
  <li><b>No-shows and walkovers.</b> Does a no-show count as one loss (dropping the player to the
      losers&#8217; side) or as immediate elimination?</li>
  <li><b>Ladies&#8217; entries below 33 or above 64</b> at Circuits 2 and 3 &#8212; agree the
      bracket-size rule now rather than at the draw.</li>
</ol>
</section>

<section class="page-break">
<h2>Appendix &#8212; what this needs from the platform</h2>
<p>For the engineering team. The Circuit stage already exists in the system as a capped,
knockout-bracket stage, but this format needs more than the current model expresses.</p>
<table>
  <thead><tr><th>Area</th><th>Today</th><th>Needed</th></tr></thead>
  <tbody>
    <tr><td>Bracket model</td>
      <td><code>knockout_brackets</code> &#8212; one row per stage and category, with rounds hanging
          off it. No concept of a winners&#8217; or losers&#8217; side.</td>
      <td>A way to express two sides and the crossover between them.</td></tr>
    <tr><td>Loser routing</td>
      <td><code>fixtures</code> record two participants and a result. Where the <i>loser</i> goes
          next is not modelled &#8212; single elimination never needed it.</td>
      <td>Each fixture needs a destination for the loser as well as the winner.</td></tr>
    <tr><td>Race length</td>
      <td>No <code>race_to</code> field exists anywhere in the schema.</td>
      <td>Race length per round &#8212; 6 in Round 1, 5 in Round 2 &#8212; so results can be
          validated against it.</td></tr>
    <tr><td>Round ordering</td>
      <td><code>rounds</code> carry a name only.</td>
      <td>Explicit ordering, so the four Round 1 waves and six Round 2 rounds sequence
          deterministically.</td></tr>
    <tr><td>Byes</td>
      <td><code>fixtures.walkover_kind</code> exists for walkovers.</td>
      <td>A bye is not a walkover &#8212; nobody forfeits. Needs its own representation, plus the
          draw constraint on page 3.</td></tr>
    <tr><td>Draw scope</td>
      <td><code>draws</code> requires exactly one of <code>venue_id</code> or
          <code>region_id</code>, and <code>formula_group_count</code> is mandatory.</td>
      <td>A Circuit draw is national and has no groups, so it fits neither slot as the table
          stands.</td></tr>
  </tbody>
</table>
<p class="cap">Based on the schema as at 2 November 2026. None of this is a blocker for agreeing the
format &#8212; it is the build list that follows from it.</p>
</section>

<footer>SportPesa National Pool Circuit 2026/27 &#183; Circuit stage format, draft v1 &#183;
Prepared for committee review. Figures assume full fields of 128 men and 55 ladies.</footer>
</body></html>'''

html = (HTML.replace("__WINNERS__", BH.winners_block())
            .replace("__LOSERS__", BH.losers_block())
            .replace("__ROUND2__", BH.round2_block())
            .replace("__MEN__", men)
            .replace("__LADIES__", ladies)
            .replace("__LADDER__", ladder()))
io.open("circuit-format.html", "w", encoding="utf-8").write(html)
print("wrote circuit-format.html", len(html), "bytes")
