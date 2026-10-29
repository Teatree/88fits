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
- Each emitter's **Speed (m/s)**: how fast its bullets fly (the hero walks about 5).

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

## Anything else

- **JSON…** (next to Save attack) opens the whole attack as text you can edit, also keys without a box. Press
  **Apply**, then Save attack. A typing mistake is shown with its line and nothing changes.
- If the build (or the tests) is running when you save, the file is still saved at once; the import into the game
  follows by itself when the build is done, and the status line says whether the build being made has your change.
