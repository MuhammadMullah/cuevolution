# -*- coding: utf-8 -*-
# Circuit bracket rendered in the CueVerse prototype's visual grammar
# (screens/P-Bracket.dc.html): round-titled columns of two-row match cards,
# 20px rounded merge connectors, Figtree, #e6e6e6 borders, grey losers.
CARD_H, GAP, W = 46, 8, 150
INK, MUTED, LINE = "#141818", "#696d6c", "#e6e6e6"
WIN = ("#ddf3d3", "#3b7530")
LOS = ("#fff0e8", "#b8491a")

def card(a, sa, b, sb, seed_a="", seed_b="", tbd=False, bg="#ffffff"):
    """One match. The side with the higher score is bold ink; the other greys out."""
    if tbd:
        aw = bw = 500; ac = bc = MUTED
        border = "1.5px dashed #8a8a8a"
    else:
        a_wins = int(sa) > int(sb)
        aw, bw = (700, 500) if a_wins else (500, 700)
        ac, bc = (INK, MUTED) if a_wins else (MUTED, INK)
        border = "1px solid %s" % LINE
    row = ('<span class="mr" style="font-weight:{w};color:{c}">'
           '<span class="seed">{s}</span><span class="nm">{n}</span>'
           '<span class="scr">{sc}</span></span>')
    return ('<div class="m" style="width:{W}px;background:{bg};border:{bd}">'
            '{ra}<span style="height:1px;background:{ln}"></span>{rb}</div>').format(
        W=W, bg=bg, bd=border, ln=LINE,
        ra=row.format(w=aw, c=ac, s=seed_a, n=a, sc=sa),
        rb=row.format(w=bw, c=bc, s=seed_b, n=b, sc=sb))

def chip(text, sub, kind):
    bg, fg = WIN if kind == "win" else LOS
    return ('<div class="m" style="width:{W}px;background:{bg};border:1px solid {fg};'
            'justify-content:center;align-items:center;text-align:center">'
            '<span style="font-weight:700;color:{fg};font-size:12px">{t}</span>'
            '<span style="color:{fg};font-size:10px;line-height:13px">{s}</span></div>').format(
        W=W, bg=bg, fg=fg, t=text, s=sub)

def column(title, items, H):
    return ('<div style="display:flex;flex-direction:column;gap:8px">'
            '<div class="ov" style="height:14px;white-space:nowrap">{t}</div>'
            '<div class="col" style="height:{H}px">{i}</div></div>').format(
        t=title, H=H, i="".join(items))

def merge_links(n, H):
    """n cards funnelling into n/2 — geometry copied from the prototype."""
    one = ('<div style="height:{h}px;display:flex;align-items:center">'
           '<div style="width:20px;align-self:stretch;border:2px solid #8a8a8a;'
           'border-left:0;border-radius:0 6px 6px 0"></div>'
           '<div style="width:20px;border-top:2px solid #8a8a8a"></div></div>')
    body = "".join(one.format(h=H // n) for _ in range(n // 2))
    return ('<div style="display:flex;flex-direction:column;gap:8px">'
            '<div style="height:14px"></div>'
            '<div class="col" style="height:{H}px">{b}</div></div>').format(H=H, b=body)

def straight_links(n, H):
    one = ('<div style="height:2px;display:flex;align-items:center">'
           '<div style="width:40px;border-top:2px solid #8a8a8a"></div></div>')
    return ('<div style="display:flex;flex-direction:column;gap:8px">'
            '<div style="height:14px"></div>'
            '<div class="col" style="height:{H}px">{b}</div></div>').format(
        H=H, b="".join(one for _ in range(n)))

def block(cols):
    return '<div class="brk" style="display:flex">%s</div>' % "".join(cols)

def H_for(n):
    return n * CARD_H + (n - 1) * GAP

# ---------------------------------------------------------------- the example
WB1 = [("Peter Omondi","6","Daniel Kariuki","2","1","16"),
       ("Dennis Kiprop","6","Tom Gitau","4","3","10"),
       ("Achieng Wanjiru","6","Lucy Chebet","1","2","11"),
       ("Kevin Mwangi","6","Mercy Atieno","5","6","12"),
       ("Samuel Mutua","6","Eric Njoroge","3","4","14"),
       ("Faith Njeri","6","Diana Muthoni","5","8","15"),
       ("Brian Otieno","6","Collins Ouma","4","7","13"),
       ("Joseph Kamau","6","Ivy Akinyi","2","9","5")]
WB2 = [("Peter Omondi","6","Dennis Kiprop","3","1","3"),
       ("Achieng Wanjiru","4","Kevin Mwangi","6","2","6"),
       ("Samuel Mutua","6","Faith Njeri","2","4","8"),
       ("Brian Otieno","6","Joseph Kamau","5","7","9")]
LB1 = [("Tom Gitau","6","Daniel Kariuki","2","10","16"),
       ("Lucy Chebet","6","Mercy Atieno","4","11","12"),
       ("Eric Njoroge","6","Diana Muthoni","1","14","15"),
       ("Collins Ouma","6","Ivy Akinyi","3","13","5")]
LB2 = [("Dennis Kiprop","6","Tom Gitau","4","3","10"),
       ("Achieng Wanjiru","6","Lucy Chebet","2","2","11"),
       ("Faith Njeri","3","Eric Njoroge","6","8","14"),
       ("Joseph Kamau","6","Collins Ouma","5","9","13")]
R2 = [("Peter Omondi","","Dennis Kiprop","","1","3"),
      ("Kevin Mwangi","","Achieng Wanjiru","","6","2"),
      ("Samuel Mutua","","Eric Njoroge","","4","14"),
      ("Brian Otieno","","Joseph Kamau","","7","9")]

def cards(rows, tbd=False):
    return [card(a, sa, b, sb, s1, s2, tbd=tbd) for a, sa, b, sb, s1, s2 in rows]

def winners_block():
    H = H_for(8)
    out = [chip("THROUGH", "0 losses", "win") for _ in range(4)]
    return block([column("WB Round 1 &#183; race to 6", cards(WB1), H),
                  merge_links(8, H),
                  column("WB Round 2 &#183; race to 6", cards(WB2), H),
                  straight_links(4, H),
                  column("Undefeated", out, H)])

def losers_block():
    H = H_for(4)
    out = [chip("THROUGH", "1 loss", "los") for _ in range(4)]
    return block([column("LB Round 1 &#183; race to 6", cards(LB1), H),
                  straight_links(4, H),
                  column("LB Round 2 &#183; crossover", cards(LB2), H),
                  straight_links(4, H),
                  column("Survivors", out, H)])

def round2_block():
    H = H_for(4)
    return block([column("Round 2 &#183; race to 5 &#183; undefeated v survivor",
                         cards(R2, tbd=True), H)])
