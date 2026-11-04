# -*- coding: utf-8 -*-
# Round 1 double-elimination flow. Every label is passed in: the ladies' bracket
# is NOT the men's numbers halved (55 players in 64 slots, 23 in the losers' side).
# Colour overrides use style="fill:..." not fill="...": a stylesheet rule beats a
# presentation attribute in SVG, so fill="#fff" inside .nt renders invisible.

TPL = u'''<svg viewBox="0 0 1280 540" xmlns="http://www.w3.org/2000/svg" class="flow">
  <defs>
    <marker id="aG{s}" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto">
      <path d="M0,0 L7,3 L0,6 z" fill="#16a34a"/></marker>
    <marker id="aR{s}" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto">
      <path d="M0,0 L7,3 L0,6 z" fill="#e32219"/></marker>
    <marker id="aA{s}" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto">
      <path d="M0,0 L7,3 L0,6 z" fill="#d9a02b"/></marker>
    <marker id="aK{s}" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto">
      <path d="M0,0 L7,3 L0,6 z" fill="#9e9ea7"/></marker>
    <marker id="aD{s}" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto">
      <path d="M0,0 L7,3 L0,6 z" fill="#16152b"/></marker>
  </defs>

  <rect x="20" y="58" width="1020" height="118" rx="12" fill="#f0faf3" stroke="#dcf3e4"/>
  <rect x="20" y="222" width="1020" height="118" rx="12" fill="#fdecea" stroke="#fbd5d0"/>
  <text x="32" y="48" class="lane">WINNERS SIDE &#183; still unbeaten</text>
  <text x="32" y="212" class="lane">LOSERS SIDE &#183; one loss, still alive</text>
  <text x="32" y="398" class="lane" style="fill:#9e9ea7">ELIMINATED &#183; two losses</text>

  <rect x="40" y="80" width="210" height="74" rx="10" fill="#ffffff" stroke="#dbdbde"/>
  <text x="145" y="103" class="nt">WB Round 1</text>
  <text x="145" y="124" class="nn">{wb1_n}</text>
  <text x="145" y="143" class="ns">{wb1_m}</text>

  <rect x="300" y="80" width="210" height="74" rx="10" fill="#ffffff" stroke="#dbdbde"/>
  <text x="405" y="103" class="nt">WB Round 2</text>
  <text x="405" y="124" class="nn">{wb2_n}</text>
  <text x="405" y="143" class="ns">{wb2_m}</text>

  <rect x="820" y="80" width="210" height="74" rx="10" fill="#f0faf3" stroke="#16a34a" stroke-width="1.5"/>
  <text x="925" y="112" class="nt" style="fill:#0e6a30">{und} UNDEFEATED</text>
  <text x="925" y="134" class="ns" style="fill:#0e6a30">0 losses</text>

  <rect x="300" y="244" width="210" height="74" rx="10" fill="#ffffff" stroke="#dbdbde"/>
  <text x="405" y="267" class="nt">LB Round 1</text>
  <text x="405" y="288" class="nn">{lb1_n}</text>
  <text x="405" y="307" class="ns">{lb1_m}</text>

  <rect x="560" y="244" width="210" height="74" rx="10" fill="#ffffff" stroke="#dbdbde"/>
  <text x="665" y="265" class="nt">LB Round 2 &#183; crossover</text>
  <text x="665" y="287" class="nn">{lb2_n}</text>
  <text x="665" y="306" class="ns">{lb2_m}</text>

  <rect x="820" y="244" width="210" height="74" rx="10" fill="#fcefcb" stroke="#d9a02b" stroke-width="1.5"/>
  <text x="925" y="276" class="nt" style="fill:#9c7318">{sur} SURVIVORS</text>
  <text x="925" y="298" class="ns" style="fill:#9c7318">1 loss</text>

  <rect x="560" y="412" width="210" height="50" rx="10" fill="#f3f3f4" stroke="#dbdbde" stroke-dasharray="4 3"/>
  <text x="665" y="442" class="ns" style="fill:#9e9ea7">{out1} eliminated</text>
  <rect x="820" y="412" width="210" height="50" rx="10" fill="#f3f3f4" stroke="#dbdbde" stroke-dasharray="4 3"/>
  <text x="925" y="442" class="ns" style="fill:#9e9ea7">{out2} eliminated</text>

  <rect x="1070" y="80" width="180" height="238" rx="12" fill="#16152b"/>
  <text x="1160" y="170" class="nt" style="fill:#ffffff">ROUND 2</text>
  <text x="1160" y="212" class="xl" style="fill:#ffffff">{r2}</text>
  <text x="1160" y="234" class="ns" style="fill:#9e9ea7">players &#183; race to 5</text>

  <path d="M250,117 L292,117" stroke="#16a34a" stroke-width="2" fill="none" marker-end="url(#aG{s})"/>
  <text x="271" y="108" class="el" style="fill:#0e6a30">{a_win}</text>

  <path d="M145,154 L145,281 L292,281" stroke="#e32219" stroke-width="2" fill="none" marker-end="url(#aR{s})"/>
  <text x="208" y="274" class="el" style="fill:#a81810">{a_drop1}</text>

  <path d="M510,117 L812,117" stroke="#16a34a" stroke-width="2" fill="none" marker-end="url(#aG{s})"/>
  <text x="661" y="108" class="el" style="fill:#0e6a30">{a_win2}</text>

  <path d="M405,154 L405,196 L665,196 L665,236" stroke="#e32219" stroke-width="2" fill="none" marker-end="url(#aR{s})"/>
  <text x="535" y="189" class="el" style="fill:#a81810">{a_drop2}</text>

  <path d="M510,281 L552,281" stroke="#d9a02b" stroke-width="2" fill="none" marker-end="url(#aA{s})"/>
  <text x="531" y="272" class="el" style="fill:#9c7318">{a_lb}</text>

  <path d="M405,318 L405,437 L552,437" stroke="#9e9ea7" stroke-width="1.5" fill="none"
        stroke-dasharray="4 3" marker-end="url(#aK{s})"/>
  <path d="M770,281 L812,281" stroke="#d9a02b" stroke-width="2" fill="none" marker-end="url(#aA{s})"/>
  <path d="M665,318 L665,437 L812,437" stroke="#9e9ea7" stroke-width="1.5" fill="none"
        stroke-dasharray="4 3" marker-end="url(#aK{s})"/>

  <path d="M1030,117 L1062,117" stroke="#16152b" stroke-width="2" fill="none" marker-end="url(#aD{s})"/>
  <path d="M1030,281 L1062,281" stroke="#16152b" stroke-width="2" fill="none" marker-end="url(#aD{s})"/>
</svg>'''

MEN = dict(s="m",
    wb1_n="128 players", wb1_m="64 matches &#183; race to 6",
    wb2_n="64 players",  wb2_m="32 matches &#183; race to 6",
    lb1_n="64 players",  lb1_m="32 matches &#183; race to 6",
    lb2_n="64 players",  lb2_m="32 matches &#183; race to 6",
    und="32", sur="32", out1="32", out2="32", r2="64",
    a_win="64 winners", a_drop1="64 losers drop", a_win2="32 win through",
    a_drop2="32 drop with 1 loss", a_lb="32")

LADIES = dict(s="w",
    wb1_n="55 players", wb1_m="23 matches + 9 byes",
    wb2_n="32 players", wb2_m="16 matches &#183; race to 6",
    lb1_n="23 players", lb1_m="7 matches + 9 walkovers",
    lb2_n="32 players", lb2_m="16 matches &#183; race to 6",
    und="16", sur="16", out1="7", out2="16", r2="32",
    a_win="23 winners + 9 byes", a_drop1="23 losers drop", a_win2="16 win through",
    a_drop2="16 drop with 1 loss", a_lb="16")

def diagram(cfg):
    return TPL.format(**cfg)
