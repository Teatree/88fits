# How to change a boss's bullet heaven yourself

The three bullet-heaven attacks are the Tumbleweed King's **Royal Dust Devil**, the Gila Grande's **Venom Monsoon** and
the Brander's **Hellbrand Mandala**. Each one is a file you can change in the Level Editor; nothing needs code.

1. Open the Level Editor (`tools\level_editor.cmd`) and go to the **Boss attacks** tab.
2. Click the attack in the list on the left (the ones marked "pattern").
3. Change the boxes below. Every box shows the game's default in grey when it is empty; the **?** next to a box says
   what it does. The preview from above (drag the slider, or **▶ Play**) shows the bullets to scale.
4. Press **Save attack** (or Ctrl+S). The next fight plays it.

The tab has the same help in its **How do I change it?** fold, above the preview.

## How long it lasts

- **Timing → Bullets for (s)**: the seconds of bullets after the warning. Now: King 16, Gila 14, Brander 18.
- **Tell (s)** is the warning before it (2 s); **Spent for (s)** is how long he stays dazed after it (2.5 s).
- Each emitter's **From (share)** and **To (share)** are shares of the bullet time (0.15 to 0.9 = from 15% to 90% of
  it), so making the attack longer keeps its shape.

## How far the bullets fly

- **Projectile → Range (m)**: a bullet shrinks away this many metres from where the boss stood. Now: King 48, Gila 44,
  Brander 36. (The phone shows about 12 m round the hero.)
- Each emitter's **Speed (m/s)**: how fast its bullets fly (the hero walks about 5). Pass 115 made every one 50% faster
  (the King's arms 4.8, his rings 3.6; the Gila's fans 4.2 and 3.6; the Brander's rose 4.5, his spiral 3.0, his finale
  pull 11.25).

## How far apart the bullets are

Each emitter (a spiral, ring, fan, sweep, wall or rose) has its own boxes:

- **Bullets a volley**: fewer bullets = more room between them. (The King's ring: 16, was 20.)
- **Spread (°)** (spiral, fan, sweep): the same bullets over a wider spread = more room between them.
- **Opening** (a ring's degrees left open, a wall's metres left open): the gap to run through.
- **Volleys a second**: lower = more room between one volley and the next along the same line. (The King's spiral: 3.6,
  was 4.5.)
- The line under the preview says how many bullets are in the air at most. Keep it under 600 for the phone.

## When it comes, and how often

- **When it comes → Not before (s)**: it never comes sooner in the fight.
- **First at HP below**: the first one comes when the boss falls under this share of his HP...
- **...or at the latest (s)**: ...or this many seconds into the fight, whichever is first.
- **Then every (s)**: the next one comes this many seconds after the last one is **completely over**: the countdown
  starts only when the warning, all the bullets and his dazed seconds are done. (A 20 s attack with "every 45" means
  45 s of normal fighting between two of them.) He still finishes whatever attack he is in first.
- Each of these three can be **fixed** (one number) or a **range** (a min and a max): pick "range" in the box's menu
  and type both. The game then picks a number between them: **Not before** and **At the latest** once per fight, **Then
  every** afresh after each attack. "Not before: range 10 to 15" = somewhere between 10 s and 15 s, different every fight.
- The line **In a fight** under the preview shows when the first three can start and end, earliest to latest.

## The barrier (pass 115)

Each of the three raises its own 3D wall out of the sand as the warning begins, round the boss and you: the King a fence
of staked, smouldering tumbleweeds and ropes, the Gila a hedge of spiny organ-pipe cactus with purple venom blooms, the
Brander an iron fence with white-hot spear heads, a red-hot rail and branding irons. It comes up on your side first and
runs round the ring; it holds you inside while the bullets fly; it falls apart (the posts topple and sink, the
tumbleweeds roll away) as the bullets end and the boss is dazed. The rows are in the tab's **The barrier** section.

- **The reach rule.** With a barrier the attack only begins when you are within its reach of the boss (the preview's
  white dashed circle; the line **Barrier:** under the preview says how far). When it is due and you are further off,
  it waits, and begins the moment you come in (its clock is not reset). So the wall never comes up on you: you always
  stand at least half a metre inside it when it rises.
- **Barrier**: the look (tumbleweed fence, cactus fence, iron fence) or **none** (no wall and no reach rule).
- **Where it stands**: **range** = the **Inset** (1 m) inside the bullets' **Range**, so every spot inside can be hit
  (now: King 47 m, Gila 43 m, Brander 35 m round him; you are held within about 0.85 m of it); **fixed** = at the
  **Radius** you type. The phone shows about 12 m round you: at the range the wall is off the screen until you run out
  to it; **fixed** at 12 to 16 m keeps it on the screen while you dodge (the bullets then vanish at it).
- **Height**, **Thickness**: how tall and thick it is (you stop at its inner face, the bullets vanish there).
- **Rise (s)**, **Spread (s)**, **Fall (s)**: how long a stretch takes to come up, how long the rise takes to run round
  the ring, how long a piece takes to fall apart.
- **Stands**: **until the bullets end** (it falls as he is dazed and you are free to go) or **until his dazed seconds
  end too**.
- **Barrier colour ×** (times its own paint; white = as made) and **Glow colour** (the embers, the blooms, the hot iron).
- **Holds the hero**: you cannot cross it while it stands (walking, shoved, thrown or leaping, you slide along it; a
  Teleport lands you inside it). **Creatures**: kept on their side (the ones outside pile up against it) or walk through.
  **Bullets at it**: vanish at it with a spark, or fly on to their range.

## Anything else

- **JSON…** (next to Save attack) opens the whole attack as text you can edit, also keys without a box. Press
  **Apply**, then Save attack. A typing mistake is shown with its line and nothing changes.
- If the build (or the tests) is running when you save, the file is still saved at once; the import into the game
  follows by itself when the build is done, and the status line says whether the build being made has your change.
