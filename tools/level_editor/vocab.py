"""The Level Editor's vocabularies (pass 66): every list the asset editors offer in a select, with the game's defaults,
as Python tables, and `check_against_source()` which reads the Godot sources with regexes and says where a table has
drifted from the code (the selftest runs it, so a reshaped constant fails loudly instead of quietly offering a stale
list). Every list here is listable, not extendable: a new brain, attack, behaviour or stat needs code ("ask Claude"),
and the page's select footers say so (NOTE below).

    table(content_dir, game_dir, combos_seen=()) -> the dict GET /api/vocab serves
    check_against_source(game_dir) -> [problem strings]   (empty = the tables match the code)

Standard library only (the server imports this).
"""
import glob
import json
import os
import re

NOTE = "a new kind needs code: ask Claude"

# ---------------------------------------------------------------- creatures (EnemyManager.gd, EnemyDef.gd, JsonContent._enemy)

# the brains `_steer` dispatches on (EnemyManager.gd `match def.brain:`); an unknown brain chases
BRAINS = ["chase", "flock", "kite", "charge", "kamikaze", "artillery", "boss", "dummy", "ambush", "caster", "support", "sniper"]
# the blocks a brain reads (the form opens these cards first; any block may be added to any brain: "untested in play")
BRAIN_BLOCKS = {"chase": [], "flock": [], "kite": ["ranged"], "charge": ["charge"], "kamikaze": ["kamikaze"],
                "artillery": ["artillery"], "boss": ["boss"], "dummy": ["ranged"], "ambush": ["ambush", "ranged"],
                "caster": ["caster", "boss"], "support": ["support"], "sniper": ["sniper"]}
# only `boss` and `elite` change behaviour; the rest are labels (and the map's skin roles)
ARCHETYPES = ["walker", "swarmer", "spitter", "brute", "tank", "runner", "elite", "boss"]
ARCHETYPES_MEANINGFUL = ["elite", "boss"]
BADGES = ["", "crown", "skull", "gear", "none"]
FACES = ["right", "left", "straight"]
TELEGRAPHS = ["line", "ring", "ring_at_hero", "sector", "fan", "spokes", "none"]
# `ranged.shot` / `spit_volley.shot`: the projectile's look; anything else is the green spit; `harpoon: true` is its own kind
SHOT_KINDS = ["", "pellet", "spike", "shard", "harpoon"]
# the keys every attack of a `boss.attacks` script shares, with the game's defaults (None = no default: absent means off)
ATTACK_COMMON = {"name": "", "windup": 1.0, "telegraph": "none", "reach": None, "min_range": None, "max_range": None,
                 "chance": None}  # pass 95 (lane BOSS): rolled as its turn comes; a miss skips to the next attack
# attack name -> its own keys with defaults, the telegraph it is drawn with by convention, whether it lands at
# `atk_target` (set only by telegraph `ring_at_hero`: slam_at, burrow and boulder need it)
ATTACKS = {
    "roll": {"keys": {"speed": 12.0, "duration": 1.2, "damage": 25.0, "length": None}, "telegraph": "line", "needs_ring_at_hero": False},
    "spawn_ring": {"keys": {"enemy": "", "count": 10}, "telegraph": "none", "needs_ring_at_hero": False},
    "slam_at": {"keys": {"radius": 2.6, "damage": 18.0, "knockback": 6.0}, "telegraph": "ring_at_hero", "needs_ring_at_hero": True},
    "blink": {"keys": {"to": "", "distance": 8.0}, "telegraph": "none", "needs_ring_at_hero": False},
    # pass 73 (lane GROUND): the visible sink, the predicted spot and its warning, the throws (EnemyManager._burrow_*)
    "burrow": {"keys": {"radius": 5.0, "damage": 28.0, "knockback": 8.0, "sink": 0.0, "rise": 0.4, "predict": 0.0, "warn": 0.4,
                        "mound": True, "throw_up": 0.0, "throw_out": 0.0, "throw_air": None, "throw_control": 0.15,
                        "creature_up": 0.0, "creature_out": 0.0, "creature_damage": 0.0},
               "telegraph": "ring_at_hero", "needs_ring_at_hero": True},
    "rain": {"keys": {"count": 10, "interval": 0.3, "spread": 5.0, "radius": 1.6, "damage": 14.0, "warn": 0.55, "spawn": "", "pillar": False, "knockback": 0.0}, "telegraph": "none", "needs_ring_at_hero": False},
    "erupt": {"keys": {"count": 10, "interval": 0.3, "spread": 5.0, "radius": 1.6, "damage": 14.0, "warn": 0.55, "spawn": "", "pillar": False, "knockback": 0.0}, "telegraph": "none", "needs_ring_at_hero": False},
    "spit_volley": {"keys": {"count": 7, "spread_deg": 90.0, "damage": 12.0, "straight": False, "speed": 14.0, "splash": 0.5, "life": 1.0, "shot": "", "knockback": 0.0, "length": 14.0}, "telegraph": "fan", "needs_ring_at_hero": False},
    "slam": {"keys": {"radius": 6.0, "damage": 30.0, "knockback": 6.0, "lift": None}, "telegraph": "ring", "needs_ring_at_hero": False},
    "rumble": {"keys": {"count": 7, "spread_deg": 90.0, "length": 14.0, "speed": 13.0, "width": 1.2, "damage": 16.0, "knockback": 10.0, "lift": 3.0}, "telegraph": "fan", "needs_ring_at_hero": False},
    "brand": {"keys": {"length": 16.0, "life": 9.0, "width": 1.1, "damage": 12.0, "tick": 0.5}, "telegraph": "line", "needs_ring_at_hero": False},
    "tumbleweed_volley": {"keys": {"count": 12, "speed": 9.0, "damage": 14.0, "life": 2.6, "knockback": 14.0, "lift": 2.5, "spoke_length": None}, "telegraph": "spokes", "needs_ring_at_hero": False},
    "swoop": {"keys": {"count": 14, "duration": 0.8, "fall": 0.45, "radius": 6.5, "deg": 180.0, "damage": 24.0, "knockback": 14.0, "lift": 3.0, "throw": 12.0, "throw_radius": 1.8}, "telegraph": "sector", "needs_ring_at_hero": False},
    "boulder": {"keys": {"flight": 1.6, "radius": 4.6, "damage": 30.0, "knockback": 26.0, "lift": 6.0, "creature_frac": 0.5, "throw": 22.0, "throw_radius": 6.5, "size": 1.7, "arc": 9.0}, "telegraph": "ring_at_hero", "needs_ring_at_hero": True},
    # pass 95 (lane BOSS): the King's jump and three stomps (EnemyManager._stomp_*: `jump` {height 2.2, up 0.35, down 0.2}),
    # the Scorpion Elite's tail beam (EnemyManager._tail_*: `beam` and `muzzle` as the sniper block's, `sfx` {aim, lock, shot})
    "stomp": {"keys": {"stomps": 3, "gap": 0.45, "jump": {}, "radius": 6.0, "damage": 18.0, "knockback": 6.0, "lift": None}, "telegraph": "ring", "needs_ring_at_hero": False},
    "tail_sniper": {"keys": {"count": 3, "gap": 0.6, "aim": 1.0, "lock": 0.4, "lines": 8, "cone_deg": 40.0, "damage": 30.8, "damage_from": "", "damage_mult": 2.0,
                             "beam": {}, "muzzle": {}, "sfx": {}}, "telegraph": "none", "needs_ring_at_hero": False},
}
# the telegraph keys each kind reads (EnemyManager.gd 3638-3676), with defaults
TELEGRAPH_KEYS = {"line": {"length": None}, "ring": {"radius": 6.0}, "ring_at_hero": {"radius": 5.0},
                  "sector": {"radius": 6.5, "deg": 180.0}, "fan": {"count": 7, "spread_deg": 90.0, "length": 14.0},
                  "spokes": {"count": 12, "spoke_length": None}, "none": {}}
# the brain blocks and their keys with the game's defaults (None = read only when present)
BLOCKS = {
    "ranged": {"keep_distance": 5.0, "range": 8.0, "telegraph": 0.6, "cooldown": 2.5, "straight": False, "cone_deg": None,
               "count": 5, "projectile_speed": None, "splash": None, "life": None, "shot": "", "knockback": 0.0,
               "pull": None, "harpoon": False, "tether": {}, "lead": False, "land_only": False, "trail": {}, "pulse": {}},
    "charge": {"windup": 0.8, "speed": 9.0, "duration": 0.7, "cooldown": 4.0, "trigger_range": 6.0, "knockback": 0.0,
               "shake": 0.0, "crouch": 0.0, "legs": 1.0, "lean": 0.0, "dust": 0.0, "shove": 0.0, "shove_walk": 0.0},
    "kamikaze": {"trigger": 1.1, "windup": 0.35, "radius": 2.6, "damage": 26.0, "knockback": 9.0},
    "artillery": {"stand_off": 28.0, "windup": 1.4, "reload": 2.5, "muzzle": {}, "missile": {}},
    "caster": {"keep_distance": 7.0, "side": 4.5, "attack_range": None},
    "support": {"keep_distance": 7.0, "range": 10.0, "interval": 4.0, "radius": 5.0, "heal": 0.25, "frenzy_seconds": 3.0},
    "ambush": {"trigger": 5.0, "rehide_distance": 12.0, "rehide_after": 6.0},
    "death_burst": {"delay": 2.0, "radius": 2.4, "damage": 12.0, "knockback": 0.0},
    "boss": {"attacks": [], "cooldown_between": 2.0, "hp_mult_per_stage": 1.6, "ring": {}},
    "elite": {"hp_mult_per_stage": 1.8},
    # pass 73 (lane SNIPER): the Saiga Sniper's brain block, and flee on hit (any creature: EnemyManager.flee_start)
    # pass 81 (lane POLISH): flee_range's default is 0 (never runs); spoil_on_hit (a hit drops the aim, no running)
    "sniper": {"stand_off": 26.0, "flee_range": 0.0, "follow": 38.0, "first": 2.5, "aim": 2.0, "lock": 1.0, "interval": 9.0,
               "interval_jitter": 1.5, "recover": 2.5, "spoil_on_hit": True, "cone_deg": 44.0, "lines": 14, "beam": {}, "muzzle": {}},
    "flee_on_hit": {"seconds": 1.0, "speed_mult": 1.8, "interrupts": True},
}
# the sub-blocks' keys (same shape), for the forms' nested rows
SUBBLOCKS = {
    "ranged.tether": {"seconds": 5.0, "away_speed": 0.7, "min_length": 1.8},
    "ranged.trail": {"color": "#62F27F", "alpha": None, "size": 1.0, "life": 1.4, "step": 0.055},
    "ranged.pulse": {"hz": 3.0, "size": 0.12, "glow": 0.3, "halo": 1.6, "color": "#9CFF6E"},
    "artillery.muzzle": {"up": 0.0, "side": 0.0, "forward": 0.0},
    "artillery.missile": {"speed": 4.0, "turn": 1.3, "damage": 22.0, "area": 1.6, "speed_of_hero": 0.0, "hit_slow": {}},
    "artillery.missile.hit_slow": {"mult": 0.5, "recover": 3.0, "shake": 0.35},
    "sniper.beam": {"length": 60.0, "width": 0.5, "seconds": 0.15, "damage_from": "", "damage_mult": 0.7, "damage": 15.4,
                    "knockback": 5.0, "creature_frac": 0.05, "creature_max": 40.0, "push": 3.0, "sparks": 1.5},
    "sniper.muzzle": {"up": 0.0, "side": 0.0, "forward": 0.0},
    "boss.ring": {"radius": 21.0, "min_radius": 8.0, "shrink": 42.0, "hold": 8.0, "burn": 0.07, "creature_burn": 0.12},
}
DROP_KEYS = {"small": 0.0, "medium": 0.0, "large": 0.0, "gold": 0.0, "chest": 0.0, "pickup": {"id": "", "chance": 0.0},
             "coins": 12, "chests": 1}
DROPS_DEFAULT = {"small": 1.0, "gold": 0.02}
VARIANCE_KEYS = {"size": 0.0, "speed": 0.0, "tints": [], "tint_strength": 0.35, "special_chance": 0.0,
                 "special": {"size": 1.5, "hp": 15.0, "damage": 2.0, "xp": 2.0, "tint": "", "tint_strength": 0.6,
                             "glow": 0.6, "chest_chance": 0.35}}  # pass 69 (lane EN): EnemyDef.SPECIAL_DEFAULTS (pass 72: 1.5, 15, chest 0.35)
SHADOW_KEYS = {"scale": 1.0, "up": 0.0, "drop": 0.0}
SFX_HOOKS = {"enemy": ["hit", "die", "attack", "spawn", "aim", "lock", "shot"], "weapon": ["fire", "hit", "place", "burst", "reload", "land"]}
# body keys with the game's defaults (JsonContent._enemy)
ENEMY_DEFAULTS = {"archetype": "walker", "brain": "chase", "hp": 10.0, "speed": 2.5, "damage": 5.0, "radius": 0.5,
                  "size": 1.0, "knockback": 0.0, "damage_reduction": 0.0, "contact_cd": 0.6, "head": 0.86,
                  "front_faces": "right", "back_faces": "right", "badge": "", "pack_size": 1, "cap_share": 1.0,
                  "max_alive": 0, "xp_mult": 1.0, "can_be_elite": True, "can_be_grabbed": True,
                  "pickup_chance_mult": 1.0, "frame_px": 128, "strip_cols": 0}
BLOOD_DEFAULT = "#C70D0D"
ENEMY_ORDER = ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
ENEMY_ANIMS_DEFAULT = {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1}
ENEMY_FPS_DEFAULT = {"run": 10.0, "die": 6.0}
# the recipe keys gen_art reads from a creature JSON or a look's `recipe` (tools only)
ENEMY_ART_KEYS = ["art_prompt", "screen", "back_hint", "back_prompt", "outline_frac", "outline_color", "cell_fill", "motion",
                  "pose", "pose_front", "walk", "hop_height", "anim_negative", "gait", "clip_fill", "directions", "view_hints",
                  "stand", "dead_hint", "death", "death_frames", "anim_seed", "run_fps", "grade", "key_sat", "key_min_value",
                  "key_cut_shadow", "key_clamp_screen", "remap_hues"]
CTL_RECIPE_KEYS = ["drivers", "prompt", "noun", "detail", "blockout", "words", "keep", "look_ref", "motion", "death_drivers",
                   "death_motion", "death_keep", "remap_hues", "dead", "fps", "directions", "screen", "outline_frac",
                   "outline_color", "side_seeds", "walk_seeds", "anatomy", "no_green", "fit_ref",
                   # pass 94 (lane REAL): the repaint method and the Wan settings
                   "paint_mode", "anchor", "style", "clay_src", "clay_fill", "init", "refine", "wan",
                   # pass 99 (lane SPIDER): per-view words, the clay a view was painted on, a view's own walk driver
                   "view_words", "clay_drivers", "view_drivers"]

# ---------------------------------------------------------------- heroes (CharacterDef.gd, JsonContent._character)

PRONOUNS = ["he", "she", "they"]
SPECIALS = ["cannot_stop", "momentum", "auto_magnet", "motherlode"]
AVAILABILITY = ["hidden", "available", "purchase"]
CURRENCIES = ["gold"]
FAVOURITE_BONUS_TYPES = ["level", "effects"]
FAVOURITE_PASSIVE_BONUS_TYPES = ["max", "level", "effects"]
# pass 67: evade_bonus (evade chance at full charge) and hit_loss (the share a hit that lands takes; 1 = the old reset)
MOMENTUM_KEYS = {"ramp_seconds": None, "speed_bonus": 0.6, "might_bonus": 0.5, "evade_bonus": 0.0, "hit_loss": 1.0}
CHAR_ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd",
              "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
CHAR_ANIMS_DEFAULT = {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
# BillboardSprite.SPEEDS: frames a second by animation-name prefix when `fps` has no row
CHAR_FPS_DEFAULT = {"idle": 4.0, "run": 14.0, "turn": 8.0, "attack": 6.0, "hit": 6.0, "die": 5.0, "cheer": 4.0}
HERO_DEFAULTS = {"order": 100, "pronoun": "they", "level_heal": 0.0, "frame_px": 256, "strip_cols": 0}
HERO_ART_KEYS = ["art_prompt", "motion", "anim_hint", "anim_negative", "anim_seed", "pose_drivers", "pose_motion",
                 "pose_driven", "pose_hint", "back_hint", "side_hint", "hurt_hint", "portrait_prompt", "still_keys",
                 "run_fps", "screen", "key_sat", "key_min_value", "key_cut_shadow", "key_clamp_screen", "grade",
                 "remap_hues", "badge", "title_pose", "title_holds", "title_camera", "title_extra_ref"]
HERO_VIEWS = ["front", "back", "side", "fd", "bd"]

# pass 70 (the Bandit check): a look's `stills` is the short name its paintings are cached under (<id>_<slug>_<view>),
# never a picture's path. Garry typed tools/dl/uploads/2d/bandit.png into it (the picture belongs in Reference), the
# upload name became a path and ComfyUI answered 500. The job form, the server (a job's spec, a look's recipe, Save) and
# the recipe editor refuse anything else with STILLS_HELP; gen_edit_stills.SLUG_RE is the same rule; "" (the asset's own
# paintings) is allowed.
STILLS_RE = re.compile(r"^[A-Za-z0-9_]{0,40}$")
STILLS_HELP = "Stills is a short name for this look's paintings, like bdb; the picture goes in Reference"


def stills_problem(value):
    """None when `value` is a stills slug (letters, digits, _; at most 40) or empty, else the plain message to show."""
    if value is None:
        return None
    if not isinstance(value, str) or not STILLS_RE.match(value):
        return "%s (letters, digits and _ only; got %s)" % (STILLS_HELP, json.dumps(value))
    return None


def bad_stills(doc):
    """[(where, message)] for every `stills` of a creature or hero JSON that is not a slug: the top level's and each look's
    recipe's (variants[CODE].recipe.stills)."""
    out = []
    if isinstance(doc, dict):
        p = stills_problem(doc.get("stills"))
        if p:
            out.append(("stills", p))
        vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
        for code, e in vs.items():
            r = e.get("recipe") if isinstance(e, dict) and isinstance(e.get("recipe"), dict) else {}
            p = stills_problem(r.get("stills"))
            if p:
                out.append(("variants.%s.recipe.stills" % code, p))
    return out

# ---------------------------------------------------------------- stats (StatSheet.gd, TextGen.gd, WeaponInstance.gd)

# StatSheet.PLAYER_DEFAULTS, read with a regex in check_against_source
PLAYER_DEFAULTS = {
    "max_hp": 100.0, "damage_reduction": 0.0, "regen": 0.0, "move_speed": 3.6, "might": 1.0, "cooldown": 1.0,
    "area": 1.0, "projectile_speed": 1.0, "duration": 1.0, "amount": 0.0, "magnet": 1.5, "luck": 0.0,
    "freeze_chance": 0.0, "crit_heal_chance": 0.0, "gold_on_hit": 0.0, "greed": 1.0, "lifesteal": 0.0, "revives": 0.0,
    "turn_rate": 180.0, "rerolls": 1.0, "skips": 2.0, "banishes": 1.0, "crit_chance": 0.01, "crit_damage": 2.0,
    "execute_frac": 0.0, "thorns": 0.0, "adrenaline_speed": 0.0, "adrenaline_might": 0.0, "overkill": 0.0,
    "cooldown_on_kill": 0.0, "xp_gain": 1.0, "ricochet": 0.0, "homing_turn": 1.0, "haste": 1.0, "evade": 0.0,
    "evade_invuln": 0.0, "shield_max": 0.0, "shield_delay": 3.0, "shield_rate": 0.5, "regen_delay": 3.0,
    "lifesteal_cap": 0.04, "heal_drop": 0.0, "coin_drop": 0.0, "hit_invuln": 0.25, "revive_hp": 0.5, "desperado": 0.0,
    "debuff_duration": 1.0, "difficulty": 0.0, "still_regen": 0.0, "still_might": 0.0, "barrel_speed": 0.0,
    "barrel_seconds": 0.0, "xp_drop_chance": 0.0, "elite_damage": 0.0, "phoenix_revive": 0.0, "hurt_speed": 0.0,
    "hurt_speed_seconds": 0.0, "powder_keg_chance": 0.0, "coin_on_hit": 0.0, "gas_mask_cap": 0.0, "kill_might": 0.0,
    "buff_duration": 1.0, "heal_mult": 1.0, "powerup_duration": 1.0, "powerup_chance": 1.0,
    # pass 69 (lane PAS's passive items): Counterpunch, Heavyweight, Snake Oil, Hot Springs, Last Stand, the Magnet's pulls
    "counter_damage": 0.0, "counter_haste": 0.0, "counter_speed": 0.0, "counter_seconds": 0.0, "heavyweight": 0.0,
    "overheal": 0.0, "heal_pulse": 0.0, "last_stand": 0.0, "xp_pull_radius": 0.0, "xp_pull_rate": 0.0,
    # pass 70 (lane LINES): the evolved lines' twists (Bucking Bronco, Prairie Fire, Marshal's Star, Mother Lode, Eureka,
    # Gold Rush)
    "bronco_chance": 0.0, "debuff_jump": 0.0, "star_block_every": 0.0, "gem_sweep_every": 0.0, "vein_chance": 0.0,
    "gold_might": 0.0,
    # pass 88 (lane MIRROR): the Upgrade board's Stakes (MirrorDanger.gd)
    "danger_hp": 0.0, "danger_attack": 0.0, "danger_speed": 0.0, "danger_bounty": 0.0,
    "boss_danger_hp": 0.0, "boss_danger_attack": 0.0, "boss_danger_speed": 0.0, "boss_danger_bounty": 0.0,
}
# player stats the code reads that are not in PLAYER_DEFAULTS (default 0 from get_stat); content uses them all
PLAYER_STATS_EXTRA = {"brand_chance": 0.0, "fire_vuln": 0.0, "poison_slow": 0.0, "poison_pass": 0.0}
# TextGen.STATS: stat -> [shown name, kind]; kinds num | pct | sec | m | deg | count
STAT_NAMES = {
    "damage": ["damage", "num"], "cooldown": ["cooldown", "sec"], "amount": ["projectiles", "count"],
    "pierce": ["pierce", "count"], "area": ["area of effect", "pct"], "speed": ["projectile speed", "num"],
    "duration": ["duration", "sec"], "knockback": ["knockback", "num"], "chains": ["chain jumps", "count"],
    "range": ["range", "m"], "spread_deg": ["spread", "deg"], "orbit_radius": ["orbit radius", "m"],
    "max_hp": ["max HP", "num"], "damage_reduction": ["damage reduction", "pct"],
    "regen": ["regen per second", "num"], "move_speed": ["move speed", "num"], "might": ["attack damage", "pct"],
    "projectile_speed": ["projectile speed", "pct"], "magnet": ["pickup radius", "m"], "luck": ["luck", "pct"],
    "greed": ["coin gain", "pct"], "revives": ["revives", "count"], "rerolls": ["rerolls", "count"],
    "skips": ["skips", "count"], "banishes": ["banishes", "count"], "hp": ["HP", "num"], "size": ["size", "pct"],
    "turn_rate": ["turn rate", "num"], "lifetime": ["turret lifetime", "sec"],
    "poison_damage": ["poison per tick", "num"], "poison_stacks": ["poison stacks", "count"],
    "poison_duration": ["poison lasts", "sec"], "lifesteal": ["life steal", "pct"],
    "fire_damage": ["burn per tick", "num"], "fire_duration": ["burns for", "sec"],
    "fire_spread": ["spread chance", "pct"], "crit_chance": ["crit chance", "pct"],
    "crit_damage": ["crit damage", "pct"], "execute_frac": ["execute threshold", "pct"],
    "thorns": ["thorns damage", "num"], "adrenaline_speed": ["speed per kill stack", "pct"],
    "adrenaline_might": ["attack damage per kill stack", "pct"], "overkill": ["overkill splash", "pct"],
    "cooldown_on_kill": ["cooldown cut per kill", "sec"], "xp_gain": ["XP gain", "pct"],
    "ricochet": ["ricochet chance", "pct"], "homing_turn": ["homing agility", "pct"],
    "haste": ["weapon speed", "pct"], "evade": ["evade chance", "pct"],
    "evade_invuln": ["untouchable after an evade", "sec"], "shield_max": ["shield", "num"],
    "shield_delay": ["shield recharge wait", "sec"], "shield_rate": ["shield recharge a second", "pct"],
    "regen_delay": ["regen wait after a hit", "sec"], "lifesteal_cap": ["life steal cap a second", "pct"],
    "heal_drop": ["cake drop chance", "pct"], "coin_drop": ["coin bag drop chance", "pct"],
    "brand_chance": ["chance a kill burns the ground", "pct"], "desperado": ["attack damage as health falls", "pct"],
    "revive_hp": ["health on revive", "pct"], "hit_invuln": ["invulnerability after a hit", "sec"],
    "cone_deg": ["cone width", "deg"], "lift": ["lift", "m"], "pin": ["pins for", "sec"],
    "plant": ["stands in the sand for", "sec"], "freeze_chance": ["chance a hit freezes for 1 s", "pct"],
    "crit_heal_chance": ["chance a crit heals 2% max HP", "pct"], "gold_on_hit": ["gold when hit", "num"],
    "debuff_duration": ["debuff duration", "pct"], "difficulty": ["difficulty", "pct"],
    "still_regen": ["regen per second standing still", "num"],
    "still_might": ["attack damage per second standing still", "pct"],
    "barrel_speed": ["move speed after a barrel", "pct"], "barrel_seconds": ["barrel boost", "sec"],
    "xp_drop_chance": ["extra XP gem chance", "pct"], "elite_damage": ["damage to Elites and bosses", "pct"],
    "phoenix_revive": ["free revive", "count"], "hurt_speed": ["move speed after a hit", "pct"],
    "hurt_speed_seconds": ["boost after a hit", "sec"], "powder_keg_chance": ["chance a kill blows up", "pct"],
    "coin_on_hit": ["chance a hit knocks a coin out", "pct"],
    "gas_mask_cap": ["damage reduction from poisoned enemies", "pct"],
    "kill_might": ["attack damage per 1,000 kills", "pct"], "buff_duration": ["buff duration", "pct"],
    "heal_mult": ["healing", "pct"], "radius": ["pillar radius", "m"],
    "powerup_duration": ["power-up duration", "pct"], "powerup_chance": ["power-up drop chance", "pct"],
    # pass 69: the new passive items' stats; kind "word" = said in words, never with a number (the Magnet's pulls)
    "counter_damage": ["damage of the next attack after an evade", "pct"], "counter_haste": ["attack speed after an evade", "pct"],
    "counter_speed": ["move speed after an evade", "pct"], "counter_seconds": ["boost after an evade", "sec"],
    "heavyweight": ["attack damage per 10 max HP", "pct"], "overheal": ["overheal past full health", "pct"],
    "heal_pulse": ["damage a heal sends out", "num"], "last_stand": ["attack damage in Last Stand", "pct"],
    "xp_pull_radius": ["EXP pull radius", "m"], "xp_pull_rate": ["pulls more often", "word"],
    # pass 70 (lane LINES); kind "rule" = said in TextGen.RULE_TEXT's words with the number inside
    "bronco_chance": ["chance a knocked-back enemy is launched", "pct"], "debuff_jump": ["debuff jumps", "rule"],
    "star_block_every": ["seconds between star blocks", "rule"], "gem_sweep_every": ["seconds between gem sweeps", "rule"],
    "vein_chance": ["chance a kill bursts into 5 XP gems", "pct"], "gold_might": ["attack damage per 100 gold gained", "pct"],
    # pass 88 (lane MIRROR); kind "hidden" = never written anywhere (the Stakes' bounty)
    "danger_hp": ["enemy HP", "pct"], "danger_attack": ["enemy attack", "pct"], "danger_speed": ["enemy speed", "pct"],
    "danger_bounty": ["", "hidden"], "boss_danger_hp": ["boss and Elite HP", "pct"],
    "boss_danger_attack": ["boss and Elite attack", "pct"], "boss_danger_speed": ["boss and Elite speed", "pct"],
    "boss_danger_bounty": ["", "hidden"],
}
# pass 69: what each new stat does, in a line (the effect pickers show it); lane PAS's help texts
STAT_HELP = {
    "counter_damage": "Counterpunch: after an evade the next weapon to fire hits for 1 + this (1.0 = double) with every hit, until it fires again or 1 s passes",
    "counter_haste": "Counterpunch: weapon speed (haste) during the boost after an evade",
    "counter_speed": "Counterpunch: move speed during the boost after an evade",
    "counter_seconds": "Counterpunch: how long the boost after an evade lasts (Buff duration stretches it); 0 = no boost",
    "heavyweight": "Heavyweight: attack damage grows with max HP: this much per whole 10 max HP (its own source on the pause screen)",
    "overheal": "Snake Oil: heals that are not regen can go past full health up to this share of max HP; hits take it first, it never fades, pink on the HP bar",
    "heal_pulse": "Hot Springs: every heal (regen too, one pulse per 0.5 s at most) hurts creatures within 3 m for this + 2 per HP healed, 40 at most",
    "last_stand": "Last Stand: a hit that leaves him under 30% health slows time to half for 2 s and adds this much attack damage; a hidden 20 s cooldown",
    "xp_pull_radius": "Magnet: every few seconds at random every EXP gem within this many metres flies to the hero (never chests, gold or power-ups); 8.5 m at most",
    "xp_pull_rate": "Magnet: the pulls' random 3-8 s wait is divided by 1 + this (1.0 = 1.5-4 s); the cards say \"pulls more often\", never a number",
    # pass 70 (lane LINES)
    "bronco_chance": "Bucking Bronco: the chance a hero's hit that knocks a plain creature back throws it up and away instead (2.8 m up, 2.5-6 m away, 0.8 s, no fall damage); bosses and Elites only take the knock",
    "debuff_jump": "Prairie Fire: how many times a burn or poison that runs out, or whose creature dies, jumps to the nearest creature within 4 m that lacks it, at its full seconds (a fire never onto the boss)",
    "star_block_every": "Marshal's Star: a gold star over the hero blocks one whole hit, then comes back after this many seconds; 0 = none",
    "gem_sweep_every": "Mother Lode: every this many seconds every XP gem on the screen flies to the hero (the first 1 s after it is taken); 0 = none",
    "vein_chance": "Eureka: the chance a kill bursts into 5 more XP gems of its size (rolled with Prospector's extra gem, so it needs xp_drop_chance above 0)",
    "gold_might": "Gold Rush: attack damage for every 100 gold gained while held (after coin gain), up to +50% in all; spending takes nothing back",
    # pass 88 (lane MIRROR): the Upgrade board's Stakes; 0.1 = +10% (the ranks add); never in the arena
    "danger_hp": "Stakes (Difficulty): regular creatures' HP (everything but a boss or an Elite by its kind)",
    "danger_attack": "Stakes (Difficulty): regular creatures' attack, their bite and every hit they throw",
    "danger_speed": "Stakes (Difficulty): regular creatures' walking speed",
    "danger_bounty": "Stakes (Difficulty): regular creatures' XP and coins (never written in the game)",
    "boss_danger_hp": "Stakes (Boss): bosses' and Elites' HP (a boss's after the seconds-of-DPS floor)",
    "boss_danger_attack": "Stakes (Boss): bosses' and Elites' attack",
    "boss_danger_speed": "Stakes (Boss): bosses' and Elites' walking speed",
    "boss_danger_bounty": "Stakes (Boss): bosses' and Elites' XP, coins and purses (never written in the game)",
}
# the weapon stats WeaponInstance.rebuild seeds before `def.base` (defaults), then the ones systems read with no seed
WEAPON_STATS = {"damage": 5.0, "cooldown": 1.0, "amount": 1.0, "pierce": 0.0, "area": 1.0, "speed": 10.0, "duration": 2.0,
                "knockback": 0.0, "chains": 0.0, "range": 8.0, "spread_deg": 30.0, "orbit_radius": 2.0, "lifetime": 12.0}
WEAPON_STATS_EXTRA = ["fire_damage", "fire_duration", "fire_spread", "poison_damage", "poison_stacks", "poison_duration",
                      "ricochet", "ricochet_damage", "mark", "spin", "pull"]
OPS = ["add", "mul", "set"]
TARGETS = ["self", "player", "all_weapons", "weapon:<id>", "tag:<tag>"]
# the default target of an Effect by where it sits in a JSON
DEFAULT_TARGETS = {"weapon.levels": "self", "passive.levels": "player", "mutation.effects": "self", "perk.effects": "player",
                   "pickup.effects": "player", "character.trait": "player", "character.trait_per_level": "player",
                   "favourite_bonus.effects": "self", "favourite_passive_bonus.effects": "player"}

# ---------------------------------------------------------------- items (WeaponDef, PassiveDef, MutationDef, W.gd)

RARITIES = ["common", "uncommon", "rare", "epic", "legendary"]
# W.RARITY_PLATE (W.gd), hex without '#'; legendary is unused by any item today (the page warns)
RARITY_PLATE = {"common": "d2cfc7", "uncommon": "8cc97a", "rare": "6b9fd8", "epic": "a585c8", "legendary": "e0a060"}
RARITY_UNUSED = ["legendary"]
# game/core/behaviors/*.gd minus the base class and the Turret (the Spawner's child)
BEHAVIOURS = ["ProjectileEmitter", "Orbiter", "Lobber", "LaserBeam", "Beam", "Spawner", "MineLayer", "MissilePod", "Thruster",
              "Smasher", "GravityGun", "ConeWave", "SunScepter",
              "SaltShaker", "Frisbee",   # pass 69: the Salt (lane SALT) and the Frisbee (lane FRIS)
              "FireBreath"]   # pass 95: the Dragon's Breath (lane BREATH)
TARGETING = ["nearest", "priority", "densest", "orbit", "random", "healthy", "forward", "ground"]
TARGETING_MEANINGFUL = ["priority", "forward", "random", "healthy"]
MUTATION_KINDS = ["element", "volume", "motion", "stance", "hero"]
PATH_KINDS = ["element", "volume", "motion"]
ELEMENTS = ["", "fire", "poison"]
WEAPON_TAGS = ["gun", "melody", "melee", "homing", "blade", "explosive", "thrown", "magic"]
WEAPON_DEFAULTS = {"behavior": "ProjectileEmitter", "targeting": "nearest", "max_level": 5, "rarity": "common", "weight": 10.0}
# pass 95 (lane PASSIVES): a new passive item is common, so its ladder has 6 levels (PASSIVE_LADDER; the game derives it)
# pass 100 (lane SMALL): `single` = a one-shot item (one level, off the ladder, never offered again once held)
PASSIVE_DEFAULTS = {"line": False, "single": False, "repeat_last_level": True, "max_level": 6, "rarity": "common", "weight": 10.0}
# the passive items' rarity ladder (PassiveDef.ladder_levels): the rungs from the rarity to legendary + Evolved + level 1
PASSIVE_LADDER = {"common": 6, "uncommon": 5, "rare": 4, "epic": 3, "legendary": 2}
MUTATION_DEFAULTS = {"kind": "motion", "rarity": "rare", "weight": 8}
# the top-level `params` keys each behaviour reads (header docs and greps of the .gd files; ProjectileEmitter's list
# includes what ProjectileManager reads off a projectile's params). Checked against the sources by key name.
PARAMS_KEYS = {
    # pass 95 (lane ITEMS): `fire_forward` marks a weapon the "Fire forward" debug switch covers (core/systems/FireForward.gd)
    "*": ["familiar", "glow", "final", "fire_forward"],
    "ProjectileEmitter": ["aura", "burst", "burst_gap", "scatter_deg", "sweep_deg", "double_every", "double_gap", "double_tap",
                          "drum_axis", "drum_step", "drum_scale", "fan_step_deg", "fire_blind", "hip_shot", "momentum_rounds",
                          "no_shells", "radius", "radius_mult", "speed_mult", "silver", "shockwave", "tint", "look", "blast",
                          "pierce_falloff", "tracer", "tracer_life", "ricochet_any", "mini_crit",
                          "size_mult", "pin", "plant", "trail_zone", "no_spin", "roll_radius", "return", "out_speed_mult",
                          "back_speed_mult", "return_damage_mult", "second_pass", "sticky", "hit_radius", "bounce", "bomblets",
                          "curare", "trace", "cloud_mult", "spiral", "turn", "wander", "trail", "tail_fade", "life",
                          "ignite_chance", "fire_blue",
                          # pass 69: Alley-Oop's launch, the ball's Heat look (lane BB), May's Trigger Happy (lane HERO)
                          "launch", "heat_look", "fire_without_target", "stream",
                          # pass 79 (lane FX): the tracer's line (tracer_step and tracer_size, the beads', are gone)
                          "tracer_width", "tracer_clear", "tracer_color", "tracer_alpha",
                          # pass 80 (lane TRAIL): the tracer's look (streak, ribbon, wisp, toon, line) and its hot part
                          "tracer_style", "tracer_hot"],
    "Orbiter": ["spin_speed", "breathe", "gyro", "lasso", "side_knock", "solid_ring", "strike", "rust", "rust_patina"],
    "Lobber": ["model", "model_scale", "model_metallic", "model_roughness", "tint", "sticky", "death_pool", "death_of",
               "land_blast", "halo", "bounce", "bomblets", "bomblet_damage_mult", "burst_spawn", "cloud_seconds",
               # pass 76 (lane DYN): the dynamite's fuse, its models by form and colour, the Drifter's mass mini crits
               "fuse", "models", "model_form", "model_colour", "fuse_tip", "mass_mini",
               # pass 79 (lane WORLD): the Dynamite Stick thrown ahead of its crowd
               "lead"],
    "Beam": ["follow", "zone", "echo_zap"],
    "LaserBeam": ["beam"],
    "ConeWave": ["cone", "tinnitus"],
    "GravityGun": ["gravity"],
    "MineLayer": ["max_mines", "trigger_radius", "extra_supply", "jackrabbit", "lay_ahead", "spring", "gold_on_kill"],
    "MissilePod": ["missile", "cluster_spin", "pollen", "hawk", "pressure", "overpressure", "cluster", "blast_fx"],
    "Smasher": ["smash", "thor", "giant_slayer"],
    "Spawner": ["max_turrets", "max_turrets_mult", "turret", "turret_fire_rate", "magnet", "tracer", "focus"],
    "Thruster": ["thrust", "crit_refund", "stunned_mult", "trail_color", "razor", "riposte", "crit_stroke"],
    "SunScepter": ["sun", "zenith", "gold_dust", "shine", "staff_tint", "handle_ring"],
    # pass 69: the Salt's patches and its floating shaker; the Frisbee's flight, disc, carry, Trick Shot and loop
    "SaltShaker": ["salt", "shaker"],
    "Frisbee": ["bend_deg", "bend_per_extra", "fan_deg", "falloff", "hit_radius", "height", "glide_seconds", "disc", "carry",
                "proc_mult", "stun", "loop"],
    # pass 95 (lane BREATH): the Dragon's Breath's cone, tick, seconds per amount, the wait, Backdraft's knock, Held
    # Breath's still block and the look, all under one `breath` key
    "FireBreath": ["breath", "fire_blue"],
}

# ---------------------------------------------------------------- perk specials (pass 69: Run.perk_param, Decoy.param)

# A perk's `special` names the mechanism the game runs; `params` tune it (Run.perk_param(special, key, default) reads
# the first held perk whose special matches). `by`: "special" = any perk id carrying it works (periodic_buff, decoy);
# "id" = the code also checks the perk's own id (Run.has_perk("<id>")), so only the perk with that id triggers it: a
# copy under a new id keeps the numbers but needs code to fire. Params: key -> the code's default (None = a list or a
# word, no number). The check below reads every default from the sources.
PERK_SPECIALS = {
    "": {"by": "special", "params": {}, "help": "none: the perk's effects only (Afterglow, Long Day)"},
    "decoy": {"by": "special", "params": {"every": 30.0, "first": 6.0, "throw_min": 4.0, "throw_max": 7.0, "flight": 0.6,
                                          "radius": 6.5, "duration": 2.0},
              "help": "Inflatable May: every `every` s (first after `first` s) she throws an inflatable double `throw_min`..`throw_max` m away; it flies `flight` s; where it lands every creature within `radius` m (Elites too, never a boss) goes for the doll for `duration` s, a pink ? over it, then it pops"},
    "periodic_buff": {"by": "special", "params": {"every": 30.0, "first": None, "seconds": 5.0, "buff": None},
                      "help": "Buzzer Beater: after `first` s (else `every`), then every `every` s, the `buff` effects (target player) for `seconds` s, a timed buff under the perk's name"},
    "timeout": {"by": "id", "params": {"every": 20.0, "first": 10.0, "side": 3.0, "pickup": None},
                "help": "Fadeaway's Timeout: drops the pickup `pickup` `side` m to his left or right, first after `first` s, then `every` s after the last one went"},
    # pass 70 (lane TRAMP): Hang Time's trampoline (core/systems/Trampoline.gd + Player.trampoline_launch)
    "trampoline": {"by": "special", "params": {"every": 20.0, "first": 10.0, "side": 3.5, "lifetime": 30.0, "radius": 1.1, "uses": 1.0,
                                               "launch_height": 4.0, "launch_distance": 8.0, "air_time": 1.1, "air_control": 0.35},
                   "help": "Hang Time: after `first` s, then `every` s after the last one folded, a 3D trampoline drops `side` m beside the hero and stands `lifetime` s; walking onto it (within `radius` m of its middle) throws him `launch_height` m up and `launch_distance` m along the way he walked, `air_time` s in the air, the stick steering at `air_control` of his walking speed, untouchable up there; it folds after `uses` jumps"},
    "overdrive": {"by": "id", "params": {"every": 5.0, "step": 0.05, "max": 0.25},
                  "help": "Jeżyk's Overdrive: every `every` s at full momentum is one gear of `step` attack damage, up to `max`; a hit that lands drops every gear"},
    "ram": {"by": "id", "params": {"thorns_mult": 3.0, "flat": 12.0, "per_level": 0.0, "shove": 9.0, "from": 0.99},
            "help": "Jeżyk's Ram: at a charge of `from` or more a creature that touches him is shoved `shove` and takes `flat` + `per_level` x level + `thorns_mult` x thorns instead of biting"},
    "high_noon": {"by": "id", "params": {"every": 30.0, "first": 20.0, "seconds": 3.0, "slow": 0.3},
                  "help": "the Drifter's High Noon: every `every` s (first after `first`) every creature moves at `slow` speed for `seconds` s"},
    "trail_dust": {"by": "id", "params": {"every": 0.22, "radius": 1.1, "seconds": 1.0, "slow": 0.25},
                   "help": "the Drifter's Trail Dust: the dust behind him slows creatures"},
    "bounty_hunter": {"by": "id", "params": {"every": 60.0, "reach": 16.0, "hp_mult": 4.0, "gold": 40.0},
                      "help": "the Drifter's Bounty Hunter: every `every` kills a creature within `reach` m is WANTED"},
    "serenade": {"by": "id", "params": {"radius": 4.0, "every": 0.3, "slow": 0.25}, "help": "Calavera's Serenade: creatures near him move slower"},
    "crescendo": {"by": "id", "params": {"per_kill": 0.01, "max": 0.4}, "help": "Calavera's Crescendo: every kill adds attack damage up to `max`; a hit drops it"},
    "grand_finale": {"by": "id", "params": {"radius": 14.0, "frac": 0.35, "throw": 16.0}, "help": "Calavera's Grand Finale: a dying boss or Elite hurts and throws the crowd round it"},
    "supply_drop": {"by": "id", "params": {"every": 40.0, "first": 15.0, "warn": 1.5, "radius": 2.6, "damage": 30.0,
                                           "damage_per_level": 4.0, "knockback": 14.0, "heart_below": 0.6, "drops": None},
                    "help": "Astro's Supply Drop: a pod crashes near her every `every` s and leaves `drops`"},
    "thruster_burst": {"by": "id", "params": {"crowd": 6.0, "reach": 2.6, "every": 8.0, "push": 28.0, "lift": 5.0, "throw": 18.0,
                                              "throw_radius": 3.2, "invuln": 0.6},
                       "help": "Astro's Thruster Burst: `crowd` creatures within `reach` m and she flies clear"},
    "suit_seals": {"by": "id", "params": {"invuln": 1.5}, "help": "Astro's Suit Seals: the level-up patch gives `invuln` s of invulnerability"},
    "deep_breath": {"by": "id", "params": {"below": 0.35, "mult": 4.0, "seconds": 6.0, "cooldown": 40.0}, "help": "Ironwood's Deep Breath: below `below` health his regen runs `mult` times over"},
    "unbroken": {"by": "id", "params": {}, "help": "Ironwood's Unbroken: hits no longer pause his regen"},
    "sunburn": {"by": "id", "params": {"bonus": 0.2}, "help": "Solenne's Sunburn: a burning or poisoned creature takes `bonus` more from her"},
    "lingering_light": {"by": "id", "params": {"harder": 0.3, "longer": 0.3}, "help": "Solenne's Lingering Light: her burns and poison tick harder and last longer"},
    "tough_love": {"by": "id", "params": {"might": 0.15, "area": 0.15, "seconds": 4.0}, "help": "Dad's Tough Love: a hit gives attack damage and area for a while"},
}
# where a params key may be read besides its behaviour's file (ProjectileManager reads a projectile's params, ...)
_PARAMS_SHARED = ["core/systems/ProjectileManager.gd", "core/systems/WeaponInstance.gd", "game/Game.gd", "core/systems/Mine.gd",
                  "core/systems/EnergyTraces.gd", "core/behaviors/WeaponBehavior.gd", "core/behaviors/Turret.gd",
                  "core/systems/FireForward.gd"]

# ---------------------------------------------------------------- quests (QuestTracker._satisfied)

QUEST_TYPES = {
    "kills_with_weapon": ["weapon", "count"], "kills_of_enemy": ["enemy", "count"], "open_chests": ["count"],
    "evolve_any": ["count"], "reach_level": ["level"], "survive_minutes": ["minutes"], "survive_minutes_no_lift": ["minutes"],
    "kills_in_run_of_enemy": ["enemy", "count"], "extract_after_stage": ["map", "stage"], "kill_boss": ["map", "stage"],
    "kills_total": ["count"], "runs_total": ["count"], "pickups_total": ["count"], "gold_total": ["count"],
    "reach_stage": ["stage"],
    # pass 100 (lane QUESTS): levels, upgrades and evolutions in one run (QuestDef's header; `id`/`kind`/`rung`/`weapon`
    # may stay empty where the header says so)
    "hero_level": ["hero", "level"], "item_level": ["kind", "id", "level", "rung"], "evolve_item": ["id", "kind"],
    "weapon_paths": ["weapon"], "items_maxed": ["kind", "count"],
}
# pass 100 (lane QUESTS): the item kinds and rarity rungs the build quests take
QUEST_ITEM_KINDS = ["any", "weapon", "card", "passive"]
QUEST_RUNGS = ["uncommon", "rare", "epic", "legendary", "evolved"]
UNLOCK_TYPES = ["character", "weapon", "passive", "map", "talent", "mode"]
QUEST_TEMPLATE_CONDITION = {"type": "kills_total", "count": 400}

# ---------------------------------------------------------------- placeholders (PlaceholderArt.gd)

PLACEHOLDER_SHAPES = ["blob", "ant", "tall", "wide", "ball", "disc"]
PLACEHOLDER_EARS = ["none", "pointed", "horn", "arms", "crown"]
PLACEHOLDER_GLYPHS = ["pea", "shotgun", "saw", "grenade", "bolt", "turret", "fist", "clock", "ring", "triple", "magnet", "heart",
                      "boot", "clover", "coin", "dice", "skip", "cross", "shield", "wing", "split", "boom", "sun", "star", "gun"]


# ---------------------------------------------------------------- what the server reads at call time

def sound_ids(content_dir):
    """{prefix: [ids]} from content/sounds/soundmap.json (the `sounds` dict), and the whole list under "all"."""
    path = os.path.join(content_dir, "sounds", "soundmap.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            sounds = json.load(f).get("sounds", {})
    except (OSError, ValueError, AttributeError):
        sounds = {}
    ids = sorted(sounds.keys()) if isinstance(sounds, dict) else sorted(str(r.get("id", "")) for r in sounds if isinstance(r, dict))
    groups = {}
    for sid in ids:
        groups.setdefault(sid.split("_", 1)[0], []).append(sid)
    groups["all"] = ids
    return groups


def folder_ids(content_dir, type_folder):
    base = os.path.join(content_dir, type_folder)
    if not os.path.isdir(base):
        return []
    return sorted(d for d in os.listdir(base) if os.path.isfile(os.path.join(base, d, d + ".json")))


def table(content_dir, game_dir=None, combos_seen=()):
    """The dict GET /api/vocab serves: every table above plus what is read from the content at call time."""
    return {
        "ok": True, "note": NOTE,
        "brains": BRAINS, "brain_blocks": BRAIN_BLOCKS, "archetypes": ARCHETYPES, "archetypes_meaningful": ARCHETYPES_MEANINGFUL,
        "badges": BADGES, "faces": FACES, "telegraphs": TELEGRAPHS, "telegraph_keys": TELEGRAPH_KEYS, "shot_kinds": SHOT_KINDS,
        "attack_common": ATTACK_COMMON, "attacks": ATTACKS, "blocks": BLOCKS, "subblocks": SUBBLOCKS,
        "drop_keys": DROP_KEYS, "drops_default": DROPS_DEFAULT, "variance_keys": VARIANCE_KEYS, "shadow_keys": SHADOW_KEYS,
        "sfx_hooks": SFX_HOOKS, "enemy_defaults": ENEMY_DEFAULTS, "blood_default": BLOOD_DEFAULT,
        "enemy_order": ENEMY_ORDER, "enemy_anims_default": ENEMY_ANIMS_DEFAULT, "enemy_fps_default": ENEMY_FPS_DEFAULT,
        "enemy_art_keys": ENEMY_ART_KEYS, "ctl_recipe_keys": CTL_RECIPE_KEYS,
        "pronouns": PRONOUNS, "specials": SPECIALS, "availability": AVAILABILITY, "currencies": CURRENCIES,
        "favourite_bonus_types": FAVOURITE_BONUS_TYPES, "favourite_passive_bonus_types": FAVOURITE_PASSIVE_BONUS_TYPES,
        "momentum_keys": MOMENTUM_KEYS, "char_order": CHAR_ORDER, "char_anims_default": CHAR_ANIMS_DEFAULT,
        "char_fps_default": CHAR_FPS_DEFAULT, "hero_defaults": HERO_DEFAULTS, "hero_art_keys": HERO_ART_KEYS, "hero_views": HERO_VIEWS,
        "player_stats": dict(PLAYER_DEFAULTS, **PLAYER_STATS_EXTRA), "player_defaults": PLAYER_DEFAULTS,
        "player_stats_extra": PLAYER_STATS_EXTRA, "stat_names": STAT_NAMES, "weapon_stats": WEAPON_STATS,
        "weapon_stats_extra": WEAPON_STATS_EXTRA, "ops": OPS, "targets": TARGETS, "default_targets": DEFAULT_TARGETS,
        "rarities": RARITIES, "rarity_plate": RARITY_PLATE, "rarity_unused": RARITY_UNUSED, "behaviours": BEHAVIOURS,
        "targeting": TARGETING, "targeting_meaningful": TARGETING_MEANINGFUL, "mutation_kinds": MUTATION_KINDS,
        "path_kinds": PATH_KINDS, "elements": ELEMENTS, "weapon_tags": WEAPON_TAGS, "weapon_defaults": WEAPON_DEFAULTS,
        "passive_defaults": PASSIVE_DEFAULTS, "passive_ladder": PASSIVE_LADDER, "mutation_defaults": MUTATION_DEFAULTS, "params_keys": PARAMS_KEYS,
        "quest_types": QUEST_TYPES, "unlock_types": UNLOCK_TYPES, "quest_template_condition": QUEST_TEMPLATE_CONDITION,
        "quest_item_kinds": QUEST_ITEM_KINDS, "quest_rungs": QUEST_RUNGS,
        "placeholder_shapes": PLACEHOLDER_SHAPES, "placeholder_ears": PLACEHOLDER_EARS, "placeholder_glyphs": PLACEHOLDER_GLYPHS,
        "sounds": sound_ids(content_dir), "elites": folder_ids(content_dir, "elites"), "pickups": folder_ids(content_dir, "pickups"),
        "combos_seen": sorted(combos_seen),
        # pass 69: a line per new stat, and the perk specials with their params' defaults
        "stat_help": STAT_HELP, "perk_specials": PERK_SPECIALS,
    }


# ---------------------------------------------------------------- the check against the Godot sources

def _read(game_dir, rel):
    try:
        with open(os.path.join(game_dir, rel), "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _match_cases(text, header_re):
    """The case labels of every GDScript `match` whose header line matches `header_re`: the string literals on the lines
    one tab deeper than the header, up to the first non-empty line at the header's depth or less."""
    out = set()
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if not re.search(header_re, line):
            continue
        depth = len(line) - len(line.lstrip("\t"))
        for nxt in lines[i + 1:]:
            if not nxt.strip():
                continue
            d = len(nxt) - len(nxt.lstrip("\t"))
            if d <= depth:
                break
            if d == depth + 1:
                body = nxt.strip()
                if body.startswith('"') and body.endswith(":"):
                    for lit in re.findall(r'"([^"]*)"', body):
                        out.add(lit)
    return out


def _const_block(text, name):
    m = re.search(r"const %s\s*:?=\s*\{(.*?)\n\}" % re.escape(name), text, re.S)
    if not m:
        return None
    return re.sub(r"#[^\n]*", "", m.group(1))


def check_against_source(game_dir):
    """Problems (strings) where a table here differs from the Godot code; [] when they agree."""
    problems = []
    em = _read(game_dir, "core/systems/EnemyManager.gd")
    if not em:
        return ["EnemyManager.gd not found under %s" % game_dir]
    brains = _match_cases(em, r"^\t+match def\.brain:")
    if brains != set(BRAINS):
        problems.append("brains: code %s / table %s" % (sorted(brains), sorted(BRAINS)))
    attacks = _match_cases(em, r'match str\(atk\.get\("name", ""\)\):')
    if attacks != set(ATTACKS):
        problems.append("attack names: code %s / table %s" % (sorted(attacks), sorted(ATTACKS)))
    tele = _match_cases(em, r'match str\(atk\.get\("telegraph", "none"\)\):') | {"none"}
    if tele != set(TELEGRAPHS):
        problems.append("telegraphs: code %s / table %s" % (sorted(tele), sorted(TELEGRAPHS)))
    for name, spec in ATTACKS.items():
        if spec["needs_ring_at_hero"] != (name in ("slam_at", "burrow", "boulder")):
            problems.append("attack %s: needs_ring_at_hero" % name)
    for name in ("slam_at", "burrow", "boulder"):
        if "atk_target" not in em:
            problems.append("atk_target is gone from EnemyManager.gd")
            break
    ss = _read(game_dir, "core/systems/StatSheet.gd")
    body = _const_block(ss, "PLAYER_DEFAULTS")
    if body is None:
        problems.append("StatSheet.PLAYER_DEFAULTS not found")
    else:
        got = {k: float(v) for k, v in re.findall(r'"([a-z_]+)":\s*([0-9.]+)', body)}
        if got != PLAYER_DEFAULTS:
            missing = sorted(set(got) ^ set(PLAYER_DEFAULTS))
            diff = sorted(k for k in got if k in PLAYER_DEFAULTS and got[k] != PLAYER_DEFAULTS[k])
            problems.append("PLAYER_DEFAULTS: keys differ %s, values differ %s" % (missing, diff))
    tg = _read(game_dir, "core/systems/TextGen.gd")
    body = _const_block(tg, "STATS")
    if body is None:
        problems.append("TextGen.STATS not found")
    else:
        got = {k: [n, kind] for k, n, kind in re.findall(r'"([a-z_]+)":\s*\["([^"]*)",\s*"([a-z]+)"\]', body)}
        if got != STAT_NAMES:
            problems.append("TextGen.STATS differs: %s" % sorted(set(got) ^ set(STAT_NAMES)))
    for k in PLAYER_STATS_EXTRA:
        if not re.search(r'"%s"' % k, em + _read(game_dir, "game/Game.gd")):
            problems.append("player stat %s is not read by EnemyManager.gd or Game.gd any more" % k)
    w = _read(game_dir, "ui/wanted/W.gd")
    m = re.search(r"const RARITY_PLATE\s*:?=\s*\{(.*?)\}", w, re.S)
    if not m:
        problems.append("W.RARITY_PLATE not found")
    else:
        got = {k: v.lower() for k, v in re.findall(r'"(\w+)":\s*Color\("([0-9a-fA-F]{6})"\)', m.group(1))}
        if got != RARITY_PLATE:
            problems.append("RARITY_PLATE: code %s / table %s" % (got, RARITY_PLATE))
    m = re.search(r"const RARITIES\s*:?=\s*\[(.*?)\]", _read(game_dir, "core/data/ContentDef.gd"))
    if m and re.findall(r'"(\w+)"', m.group(1)) != RARITIES:
        problems.append("ContentDef.RARITIES differ")
    folder = os.path.join(game_dir, "core", "behaviors")
    got = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(folder, "*.gd")))
    got = [b for b in got if b not in ("WeaponBehavior", "Turret")]
    if got != sorted(BEHAVIOURS):
        problems.append("behaviours: folder %s / table %s" % (got, sorted(BEHAVIOURS)))
    gm = _read(game_dir, "game/Game.gd")
    for b in BEHAVIOURS:
        if '"%s"' % b not in gm:
            problems.append("Game.gd does not name the behaviour %s" % b)
    shared = "\n".join(_read(game_dir, p) for p in _PARAMS_SHARED)
    for b, keys in PARAMS_KEYS.items():
        own = shared if b == "*" else _read(game_dir, "core/behaviors/%s.gd" % b) + shared
        for k in keys:
            if not re.search(r'"%s"' % re.escape(k), own):
                problems.append("params key %s is not read by %s or the shared files" % (k, b))
    qt = _read(game_dir, "core/systems/QuestTracker.gd")
    types = _match_cases(qt, r'match str\(c\.get\("type", ""\)\):')
    if types != set(QUEST_TYPES):
        problems.append("quest types: code %s / table %s" % (sorted(types), sorted(QUEST_TYPES)))
    reg = _read(game_dir, "core/autoload/Registry.gd")
    m = re.search(r"const MUTATION_ORDER\s*:?=\s*\{(.*?)\}", reg)
    if m and re.findall(r'"(\w+)"', m.group(1)) != MUTATION_KINDS:
        problems.append("Registry.MUTATION_ORDER differs from MUTATION_KINDS")
    pl = _read(game_dir, "player/Player.gd") + _read(game_dir, "core/systems/PickupManager.gd") + gm
    for s in SPECIALS:
        if 'specials.has("%s")' % s not in pl:
            problems.append("hero special %s is not read" % s)
    bb = _read(game_dir, "core/systems/BillboardSprite.gd")
    m = re.search(r"const SPEEDS\s*:?=\s*\{(.*?)\}", bb)
    if m:
        got = {k: float(v) for k, v in re.findall(r'"([a-z_]+)":\s*([0-9.]+)', m.group(1))}
        if got != CHAR_FPS_DEFAULT:
            problems.append("BillboardSprite.SPEEDS: %s" % got)
    ed = _read(game_dir, "core/data/EnemyDef.gd")
    for name in ENEMY_ORDER:
        if '"%s"' % name not in ed:
            problems.append("EnemyDef.gd does not name the animation %s" % name)
    # pass 69 (lane EN): the special's defaults the page shows are the game's (EnemyDef.SPECIAL_DEFAULTS)
    m = re.search(r"const SPECIAL_DEFAULTS\s*:?=\s*\{(.*?)\}", ed)
    if not m:
        problems.append("EnemyDef.SPECIAL_DEFAULTS not found")
    else:
        got = {k: float(v) for k, v in re.findall(r'"([a-z_]+)":\s*([0-9.]+)', m.group(1))}
        want = {k: float(v) for k, v in VARIANCE_KEYS["special"].items() if k != "tint"}
        if got != want:
            problems.append("EnemyDef.SPECIAL_DEFAULTS %s / VARIANCE_KEYS.special %s" % (got, want))
    plg = _read(game_dir, "player/Player.gd")
    for name in CHAR_ORDER:
        if '"%s"' % name not in plg:
            problems.append("Player.gd does not name the animation %s" % name)
    # pass 69: every stat with a help line is a stat the game names; the perk specials and their defaults are the code's
    for s in STAT_HELP:
        if s not in STAT_NAMES:
            problems.append("STAT_HELP names %s, which TextGen.STATS does not" % s)
    perk_src = "\n".join(_read(game_dir, p) for p in ("game/Game.gd", "core/autoload/Run.gd", "player/Player.gd",
                                                       "core/systems/EnemyManager.gd", "core/systems/Decoy.gd",
                                                       "core/systems/Trampoline.gd"))
    decoy = _read(game_dir, "core/systems/Decoy.gd")
    for sp, spec in PERK_SPECIALS.items():
        if not sp:
            continue
        if spec["by"] == "id" and 'has_perk("%s")' % sp not in perk_src:
            problems.append("perk special %s: no Run.has_perk(\"%s\") in the game (by id)" % (sp, sp))
        if spec["by"] == "special" and not re.search(r'special [!=]= "%s"' % sp, perk_src):
            problems.append("perk special %s: no `special == \"%s\"` in the game" % (sp, sp))
        for key, dflt in spec["params"].items():
            if dflt is None:
                if '"%s"' % key not in perk_src:
                    problems.append("perk special %s: the key %s is not read" % (sp, key))
                continue
            pats = [r'perk_param\("%s", "%s", ([-0-9.]+)\)' % (sp, key)]
            if sp == "decoy":
                pats.append(r'\bparam\("%s", ([-0-9.]+)\)' % key)
            if sp == "periodic_buff":
                pats.append(r'params\.get\("%s", ([-0-9.]+)\)' % key)
            found = [float(v) for pat in pats for v in re.findall(pat, decoy if sp == "decoy" and "param(" in pat and "perk_" not in pat else perk_src)]
            if not found:
                problems.append("perk special %s: %s is not read with a default" % (sp, key))
            elif float(dflt) not in found:
                problems.append("perk special %s: %s defaults to %s in the code, %s here" % (sp, key, found, dflt))
    jc = _read(game_dir, "core/data/JsonContent.gd")
    for k, v in ENEMY_DEFAULTS.items():
        if k in ("frame_px", "strip_cols"):
            continue
        if not re.search(r'd\.get\("%s",' % k, jc):
            problems.append("JsonContent._enemy does not read %s" % k)
    for b in BLOCKS:
        if not re.search(r'd\.get\("%s",' % b, jc):
            problems.append("JsonContent does not read the block %s" % b)
    return problems
