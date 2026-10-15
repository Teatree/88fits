## The kiting autopilot (pass 62, the difficulty probe's; pass 77 moved it here so the run sim drove the hero the same
## way). Pass 80 (lane BOT): the legs live in tools/bot/BotLegs.gd (the reusable bot's); this file only extends it, so
## tools/difficulty_probe.gd and the older tools and tests that preload it steer exactly as before (its dials default to
## pass 77's legs).
extends "res://tools/bot/BotLegs.gd"
