"""Icon candidates for new and repainted items, several seeds each, picked by eye (pass 46). Items drawn from a 3D model
take its render as a reference (tools/dl/<x>_ref.png, laid on the green screen first), the way the Tommy Gun's icon was
painted from its model (pass 44), so the 2D icon and the 3D object are one thing.

  python tools/gen_icon_cands.py [--only spear,cake] [--seeds 4] [--dev]
      -> tools/dl/icons<set>/<key>_c<k>.png + review_<key>.png (a job's "set": 46 unless it says, 47 for pass 47's)
  python tools/gen_icon_cands.py --pick spear=2 cake=0
      -> installs into the item's folder (content icons), art/ui/badges/<b>.png (badges) or art/ui/wanted/<x>.png (UI)

JOBS: key -> {"kind": content type or "badge" or "ui", "id": target id, "subject": what to paint, "ref": optional
render, "halo": badge glow colour, "set": the pass whose folder it paints into, "style": words in place of gen_art's
ICON_STYLE}. Content icons are finished like gen_art's icons (256 px), badges like gen_badges' (128 px, heavy outline,
halo), UI art at 256 px with a slight outline, damage sources ("source", the Results screen's rows that are not a
weapon: fire, revive, a blast, an unknown hit) like content icons into art/ui/sources/<id>.png.
"""
import io
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = os.path.join(REPO, "tools", "dl")
OUT = os.path.join(DL, "icons46")


def _out(job):
    """The folder a job paints into: icons46, or its own pass's (icons47)."""
    return os.path.join(DL, "icons" + str(job.get("set", "46")))
CONTENT = os.path.join(REPO, "game", "content")
COPY = ("Copy this exact object from the reference image: its silhouette, proportions, parts and colours, seen from the same "
        "angle. ")
JOBS = {
    # pass 54 (set 54): the Sun Scepter family and Solenne's perks; the sceptre and Zenith are painted from the model's render
    "sun_scepter": {"set": "54", "kind": "weapons", "id": "sun_scepter", "ref": "sun_scepter_ref.png",
                    "subject": COPY + "a golden sceptre: a slim dark lacquered staff with three brass bands and a small brass foot, "
                               "topped by a shining golden sun disc with eight straight pointed rays and one small white glint on the "
                               "disc's rim, held upright, seen from the side at a slight tilt"},
    "zenith": {"set": "54", "kind": "evolutions", "id": "zenith", "ref": "zenith_ref.png",
               "subject": COPY + "a golden sceptre whose sun head blazes: a big golden sun disc with twelve long rays and a second thin "
                          "brass ring round it, a white-hot corona, the slim dark staff below with brass bands, held upright"},
    # pass 55 (Garry: "Evolution Zenith - 3D looks fine, 2D doesn't"): the set-54 Zenith painted a white plate behind the
    # disc inside its ring, a wheel or a shield; the model's ring is a thin open hoop with the sky between it and the disc
    "zenith2": {"set": "55", "kind": "evolutions", "id": "zenith", "ref": "zenith_ref.png",
                "subject": COPY + "a golden sceptre whose head is a radiant sun: a glowing golden sun disc with twelve long slender "
                           "pointed golden rays fanning out all round it, and one thin brass hoop floating around the disc with "
                           "open empty space between the hoop and the disc (no fill, no plate and no shield behind it, the "
                           "background shows through), a soft warm golden glow round the head, the slim dark staff below with "
                           "brass bands and a pointed brass foot, held upright at a slight tilt"},
    "heat_stroke": {"set": "54", "kind": "mutations", "id": "heat_stroke",
                    "subject": "a small blazing yellow sun disc with short rays beating straight down as a column of golden light onto "
                               "a patch of sand that has caught fire, little orange flames licking up from it"},
    "flicker": {"set": "54", "kind": "mutations", "id": "flicker",
                "subject": "a small round golden sun disc at the top with three narrow beams of yellow sunlight fanning straight down "
                           "from it in quick flashes, each beam a slim glowing yellow wedge, bright at the sun and fading out lower "
                           "down, a small white four-point sparkle at the foot of each beam"},
    "gold_dust": {"set": "54", "kind": "mutations", "id": "gold_dust",
                  "subject": "a column of golden sunlight landing on the ground where three round gold coins lie scattered in a drift "
                             "of glittering gold dust, the coins catching the light"},
    "afterglow": {"set": "54", "screen": "blue", "kind": "perks", "id": "afterglow",
                  "subject": "a green heart glowing warmly with a small golden sun rising behind its upper edge, soft yellow rays "
                             "fanning out round it"},
    "sunburn": {"set": "54", "kind": "perks", "id": "sunburn",
                "subject": "a small bright sun with sharp rays scorching a dark red target ring on the ground, a thin curl of "
                           "smoke and a crack of orange heat across the ring"},
    "lingering_light": {"set": "54", "kind": "perks", "id": "lingering_light",
                        "subject": "a golden hourglass with sunlight pouring through it instead of sand, a thin trail of glowing "
                                   "yellow dots lingering in the air round its base"},
    "long_day": {"set": "54", "kind": "perks", "id": "long_day",
                 "subject": "a low golden sun sitting on a flat horizon line with long rays stretching sideways, a small round clock "
                            "face beside it with its hands near six, the whole thing warm and calm"},
    # pass 53: the seven weapons' new mutations and evolutions (set 53 -> tools/dl/icons53)
    "heavy_warhead": {"set": "53", "kind": "mutations", "id": "heavy_warhead",
                      "subject": "a fat stubby red-nosed rocket warhead seen from the side, its dark steel body heavy and wide, a "
                                 "bold white impact star and two short shockwave arcs at its tip"},
    "cluster_munitions": {"set": "53", "kind": "mutations", "id": "cluster_munitions",
                          "subject": "a small rocket bursting open in mid-air into a scatter of five tiny round black bomblets "
                                     "with blinking red dots, falling towards the sand"},
    "pressure_cooker": {"set": "53", "kind": "mutations", "id": "pressure_cooker",
                        "subject": "a dark steel rocket launcher tube glowing orange-hot at its mouth, heat shimmer lines rising "
                                   "off it and a small round pressure gauge on its side with the needle in the red"},
    "hellfire_battery": {"set": "53", "kind": "evolutions", "id": "hellfire_battery",
                         "subject": "a heavy black and dark-red six-tube rocket battery in two rows seen from the front three-quarter, "
                                    "every tube mouth glowing orange, two stubby fins, one rocket leaving it with a bright flame"},
    "last_stand": {"set": "53", "kind": "mutations", "id": "last_stand",
                   "subject": "a small dark grey gun turret on a tripod blowing itself apart in a bright orange explosion, pieces "
                              "of the turret flying outwards, a white flash at the centre"},
    "iron_bastion": {"set": "53", "kind": "evolutions", "id": "iron_bastion",
                     "subject": "a heavy riveted dark iron twin-barrel bunker turret with brass rivets and a brass band, set in a "
                                "ring of sandbags, a small searchlight box on top, seen from the front three-quarter"},
    "echo_zap": {"set": "53", "kind": "mutations", "id": "echo_zap",
                   "subject": "three small jagged bright blue lightning bolts striking the same spot one after another, little "
                              "white sparks scattering from where they land"},
    "critical_thinking": {"set": "53", "kind": "mutations", "id": "critical_thinking",
                          "subject": "a curved steel sabre blade with a small glowing yellow target reticle on its edge and a "
                                     "bright yellow starburst, three thin motion lines"},
    "whirlwind": {"set": "53", "kind": "evolutions", "id": "whirlwind",
                  "subject": "a broad curved scimitar with a brass guard spinning in a full circle, a pale cyan ring of wind "
                             "and motion arcs round it, small dust puffs"},
    "stunning_thrust": {"set": "53", "kind": "mutations", "id": "stunning_thrust",
                        "subject": "a spear tip striking forward with a ring of small yellow dizzy stars circling where it hits, "
                                   "short motion lines along the shaft"},
    "long_spear": {"set": "53", "kind": "mutations", "id": "long_spear",
                   "subject": "a very long thin spear with a dark wooden shaft stretching diagonally across the whole picture from "
                              "the lower left to the upper right, a small steel point, a tiny tassel at the butt"},
    "thunder_lance": {"set": "53", "kind": "evolutions", "id": "thunder_lance",
                      "subject": "a long dark walnut lance with two brass bands and a feathered tassel under its long pale "
                                 "glowing blue-white tip, a small jagged blue lightning crackle at the point, diagonal from the "
                                 "lower left to the upper right"},
    "dust_wake": {"set": "53", "screen": "blue", "kind": "mutations", "id": "dust_wake",
                  "subject": "a round brown tumbleweed rolling to the right leaving a wake of dark green dust swirling behind "
                             "and round it"},
    "dust_devil": {"set": "53", "screen": "blue", "kind": "evolutions", "id": "dust_devil",
                   "subject": "a big jet-black thorny tumbleweed rolling to the right inside a tall spinning dark green dust "
                              "devil funnel, small stones and sand lifted round it"},
    # Ironwood's spear and the War Lance (tools/blender_spear.py renders)
    "spear": {"kind": "weapons", "id": "spear", "ref": "spear_ref.png",
              "subject": COPY + "a long hunting spear lying diagonally from the lower left to the upper right: a dark wooden shaft wrapped "
                         "in red cloth at three places, a leaf-shaped polished steel point at the upper right, two white eagle feathers "
                         "with black tips hanging from a thong under the point, a small tuft of feathers at the butt"},
    "war_lance": {"kind": "evolutions", "id": "war_lance", "ref": "war_lance_ref.png",
                  "subject": COPY + "a long ceremonial war lance lying diagonally from the lower left to the upper right: a gleaming "
                             "gold shaft wrapped in deep red cloth at three places, a big leaf-shaped gilded point at the upper right, "
                             "white eagle feathers hanging under the point, glowing faintly"},
    "fire_hardened": {"kind": "mutations", "id": "fire_hardened",
                      "subject": "a leaf-shaped spear point glowing red-hot orange, flames licking back along its edges and the red "
                                 "cloth wrap behind it"},
    "spear_volley": {"kind": "mutations", "id": "spear_volley",
                     "subject": "three long spears with red cloth wraps and steel points flying side by side in a spreading fan towards "
                                "the upper right, motion lines behind them"},
    "pinning_throw": {"kind": "mutations", "id": "pinning_throw",
                      "subject": "a spear stabbed straight down into the sand, standing upright and quivering, its shaft pinning a "
                                 "torn scrap of cloth to the ground, short motion lines round the shaft"},
    # the low-health damage passive
    "desperado": {"kind": "passives", "id": "desperado",
                  "subject": "a cracked red heart with a smoking six-shooter revolver crossed in front of it, a wisp of smoke "
                             "curling from the barrel"},
    # Cake (was Cheese) and its slice
    "cake": {"kind": "passives", "id": "cake",
             "subject": "a whole round layered birthday cake with pink frosting dripping down its sides, white cream swirls on top "
                        "and one red cherry, seen from the front and a little above"},
    "cake_slice": {"kind": "pickups", "id": "cake_slice",
                   "subject": "a single triangular slice of layered cake with pink frosting on top, a stripe of cream between the "
                              "sponge layers and a red cherry, seen from the side and a little above"},
    # the Guitarra's new mutations and the guitar itself (tools/blender_guitar.py renders)
    "music_slap": {"kind": "mutations", "id": "music_slap",
                   "subject": "a big golden musical note being slapped sideways by an open hand, a white impact star and speed lines "
                              "where they meet"},
    "far_reach": {"kind": "mutations", "id": "far_reach",
                  "subject": "a wide half-circle fan of golden musical notes spreading out from a guitar's round soundhole, each note "
                             "smaller towards the edge of the fan"},
    "guitarra": {"screen": "blue", "kind": "weapons", "id": "guitarra", "ref": "guitarra_ref.png",
                 "subject": COPY + "a cartoon Mexican acoustic guitar standing tilted with its neck to the upper right: a warm yellow "
                            "top with a thin red line round its edge, green sides, a round rosette of red, white and blue triangles "
                            "round a black soundhole, a black neck and headstock with tuning pegs, six thin silver strings"},
    "requiem": {"kind": "evolutions", "id": "requiem", "ref": "requiem_ref.png",
                "subject": COPY + "a cartoon acoustic guitar standing tilted with its neck to the upper right: a glossy black top with "
                           "a thin gold line round its edge, gleaming gold sides, a white rosette round a black soundhole, a black neck "
                           "and headstock with tuning pegs, six thin silver strings"},
    # the Turret Buddy and its paths (tools/blender_turret.py renders)
    "turret_buddy": {"kind": "weapons", "id": "turret_buddy", "ref": "turret_buddy_ref.png",
                     "subject": COPY + "a small armoured gun turret: a stepped octagonal grey steel base with four sloped fins, a "
                                "squat bell-shaped body, a boxy grey steel head with a round hatch on top, one long barrel with two "
                                "red bands and a black muzzle brake pointing to the lower left"},
    "turret_family": {"kind": "evolutions", "id": "turret_family", "ref": "turret_family_ref.png",
                      "subject": COPY + "a small armoured gun turret made of polished gold: a stepped octagonal base with four sloped "
                                 "fins, a squat bell-shaped body, a boxy head with a round hatch on top, one long barrel with two dark "
                                 "red bands and a dark muzzle brake pointing to the lower left"},
    "watchtower": {"kind": "mutations", "id": "watchtower", "ref": "turret_watchtower_ref.png",
                   "subject": COPY + "a tall wooden tripod watchtower: three long wooden legs with cross braces holding a round "
                              "wooden platform high up, and on the platform a small boxy grey steel gun turret with ONE single "
                              "long barrel with red bands"},
    "bunker": {"kind": "mutations", "id": "bunker", "ref": "turret_bunker_ref.png",
               "subject": COPY + "a low gun bunker: a ring of tan sandbags round a squat grey steel turret with twin long barrels "
                          "side by side, red bands on the barrels"},
    "buddy_squad": {"kind": "mutations", "id": "buddy_squad", "ref": "turret_buddy_ref.png",
                    "subject": "two small armoured grey steel gun turrets like the one in the reference image standing side by side, "
                               "their long red-banded barrels pointing the same way, a white '2x' sign above them"},
    "dart_buddy": {"screen": "blue", "kind": "mutations", "id": "dart_buddy", "ref": "turret_buddy_ref.png",
                   "subject": COPY + "the small armoured grey steel gun turret, its barrel firing a green poison dart that leaves a "
                              "trail of green drops"},
    # Ironwood's perks
    "unbroken": {"screen": "blue", "kind": "perks", "id": "unbroken",
                 "subject": "a green heart bound with a tight band of braided leather, a small crack in the heart closing up with a "
                            "glow"},
    "deep_breath": {"screen": "blue", "kind": "perks", "id": "deep_breath",
                    "subject": "a green heart with three curling white wind lines sweeping round it, a soft green glow"},
    # the UI coin and the hit-log badges
    "coin": {"kind": "ui", "id": "coin",
             "subject": "one thick round gold coin seen straight from the front, a five-pointed star embossed in the middle, a "
                        "raised rim with small notches round the edge, warm brass gold with a bright highlight"},
    "bow": {"kind": "badge", "id": "bow", "halo": (255, 200, 120),
            "subject": "a short curved wooden hunting bow with a taut string and one arrow nocked on it pointing to the upper right, "
                       "the arrow with red fletching"},
    "heart": {"kind": "badge", "id": "heart", "halo": (120, 255, 140),
              "subject": "a plump shiny red heart with a white highlight, seen straight from the front"},
    # pass 47 (Garry's fifth list): the new line items, their evolutions and those of the four passives that became lines
    "ducktape": {"set": "47", "kind": "passives", "id": "ducktape",
                 "subject": "a thick roll of shiny silver-grey duct tape seen at a slight angle, a torn strip of tape curling off it"},
    "clover": {"set": "47", "screen": "blue", "kind": "passives", "id": "clover",
               "subject": "one bright green three-leaf clover with heart-shaped leaves on a short curved stem"},
    "hot_sauce": {"set": "47", "kind": "passives", "id": "hot_sauce",
                  "subject": "a small glass bottle of bright red hot sauce with a red screw cap and a cream label showing a red chili "
                             "pepper, a drop of sauce running down its side"},
    "barrage": {"set": "47", "screen": "blue", "kind": "passives", "id": "barrage",
                "subject": "five glowing bright green energy spheres bursting outwards in a wide fan from one point, motion streaks "
                           "behind each sphere, a bright flash at the point they burst from"},
    "almanac": {"set": "47", "kind": "passives", "id": "almanac",
                "subject": "a thick old leather-bound almanac book with brass corner guards and a golden sun emblem on its cover, a "
                           "purple ribbon bookmark hanging out, faint purple glow from its pages"},
    "quicksilver": {"set": "47", "kind": "passives", "id": "quicksilver",
                    "subject": "a shiny silver stopwatch with spread silver wings on its sides, drops of bright liquid mercury "
                               "flying off it"},
    "eagle_eye": {"set": "47", "kind": "passives", "id": "eagle_eye",
                  "subject": "a round gold marksman medal with a fierce golden eagle's eye in its centre ringed by a red target ring, "
                             "two small golden wings spread at its sides"},
    "shackles": {"set": "47", "kind": "passives", "id": "shackles",
                 "subject": "a pair of heavy black iron shackles joined by a short iron chain, a strip of silver duct tape wrapped "
                            "round the chain"},
    # the first Shackles were black iron: on the evolved plate (ink inside a brass ring) they all but vanished
    "shackles2": {"set": "47", "kind": "passives", "id": "shackles",
                  "subject": "a pair of heavy shiny light-grey steel shackles with bright white highlights joined by a short "
                             "light-grey chain, a strip of silver duct tape wrapped round the chain, light metal colours"},
    "golden_horseshoe": {"set": "47", "screen": "blue", "kind": "passives", "id": "golden_horseshoe",
                         "subject": "a gleaming golden horseshoe standing upright with its open end up, a small green four-leaf clover "
                                    "tucked in its middle, a few white sparkles round it"},
    "ghost_pepper": {"set": "47", "kind": "passives", "id": "ghost_pepper",
                     "subject": "a wrinkled glowing orange-red ghost pepper chili with a green stem, wisps of fiery red-orange steam "
                                "curling up off it"},
    # the new passive items
    "barrel_rush": {"set": "47", "kind": "passives", "id": "barrel_rush",
                    "subject": "a wooden barrel with iron hoops bursting apart into flying planks and splinters, yellow speed lines "
                               "streaking out from it"},
    # the first Barrel Rush read as a bundle of sticks (Garry: terrible): one clear barrel, one clear idea of speed
    "barrel_rush2": {"set": "47", "kind": "passives", "id": "barrel_rush",
                     "subject": "one chunky brown wooden barrel with two dark iron hoops, cracked open down its side with a few "
                                "wooden planks flying off, a cowboy boot kicking it from the left, three bold yellow speed lines "
                                "behind the boot"},
    # pass 47c: Multishot repainted (Garry: it looked weird) and four new passive items
    "multishot2": {"set": "47", "kind": "passives", "id": "multishot",
                   "subject": "three identical brass bullets flying side by side in a spreading fan towards the upper right, "
                              "short motion streaks behind each bullet"},
    "gold_tooth": {"set": "47", "kind": "passives", "id": "gold_tooth",
                   "subject": "one single shiny gold molar tooth with a bright white highlight and a small sparkle"},
    "cold_snap": {"set": "47", "kind": "passives", "id": "cold_snap",
                  "subject": "a pale icy blue six-pointed snowflake crystal with frosty white edges and a few small ice shards "
                             "around it"},
    "hush_money": {"set": "47", "kind": "passives", "id": "hush_money",
                   "subject": "a fat brown cloth money bag tied with string, a white bandage plaster stuck across it, gold coins "
                              "spilling out at its foot"},
    "vulture": {"set": "47", "kind": "passives", "id": "vulture",
                "subject": "the head and neck of a bald desert vulture with a pink bald head, a hooked yellow beak and a ruff of "
                           "dark brown feathers, a small red heart beside it"},
    "beer": {"set": "47", "kind": "passives", "id": "beer",
             "subject": "a big wooden beer tankard with two brass bands and a handle, full of golden beer with thick white foam "
                        "overflowing down its side"},
    "siesta": {"set": "47", "kind": "passives", "id": "siesta",
               "subject": "a wide straw sombrero resting on a plump white pillow, a small glowing red heart floating just above it"},
    "steady_hand": {"set": "47", "kind": "passives", "id": "steady_hand",
                    "subject": "a brown leather-gloved hand holding a silver revolver perfectly level and still, pointing to the "
                               "right, a thin straight red aiming line from its barrel"},
    "prospector": {"set": "47", "kind": "passives", "id": "prospector",
                   "subject": "a miner's pickaxe with a wooden handle leaning on a grey rock, a big glowing purple crystal gem "
                              "growing out of the rock"},
    "big_game_hunter": {"set": "47", "kind": "passives", "id": "big_game_hunter",
                        "subject": "a hunting trophy: a big bleached bull skull with long curved horns mounted on a dark wooden "
                                   "shield-shaped plaque"},
    # repaints: Second Wind's green heart was keyed see-through on the green screen, the Guillotine's blade read as a knife
    # hanging point down
    "second_wind": {"set": "47", "screen": "blue", "kind": "passives", "id": "second_wind",
                    "subject": "a solid opaque bright green heart wrapped in a white bandage, two white wind swirls curling round "
                               "it, the heart fully coloured with no see-through parts"},
    "guillotine": {"set": "47", "kind": "passives", "id": "guillotine",
                   "subject": "a tall wooden guillotine seen straight from the front: two upright wooden posts joined by a crossbeam "
                              "at the top, a wide flat rectangular steel blade spanning the whole gap between the posts near the "
                              "top, its bottom cutting edge one straight diagonal line, a rope over the crossbeam holding it up, a "
                              "wooden neck block with a round hole at the bottom between the posts"},
    # the coin, about a third simpler (Garry: too busy)
    "coin47": {"set": "47", "kind": "ui", "id": "coin",
               "subject": "one plain round gold coin seen straight from the front: a flat gold disc with one thick raised rim and "
                          "one simple flat five-pointed star in the middle, two flat tones of gold, no bevels, no notches, no "
                          "texture, no shine streaks"},
    # the Results screen's damage rows that are not a weapon
    "src_fire": {"set": "47", "kind": "source", "id": "fire",
                 "subject": "a single bright flame: an orange outer fire with a yellow core, three licking tongues at its top"},
    "src_revive": {"set": "47", "kind": "source", "id": "revive",
                   "subject": "a bright red heart with two white feathered angel wings spread out on its sides, a soft golden "
                              "glow behind it"},
    "src_blast": {"set": "47", "kind": "source", "id": "blast",
                  "subject": "a round cartoon explosion: an orange and yellow fireball with a jagged star-shaped edge, a few dark "
                             "bits of debris flying out"},
    "src_unknown": {"set": "47", "kind": "source", "id": "unknown",
                    "style": "Mobile game icon in the style of Shop Titans: one single bold symbol, thick clean black outline, "
                             "simple chunky shapes, flat cel shading with one soft highlight, centered and filling the frame with a "
                             "small margin, readable at thumbnail size, no background, no scene",
                    "subject": "one big chunky question mark symbol made of polished brass gold"},
    # pass 48 (Garry's sixth list): six new passive items, Steady Hand simpler, Trick Shot clearer, the new mutations, the new
    # evolutions and Pollen's three flowers (world pickups: the icon is the sprite on the sand)
    "phoenix_feather": {"set": "48", "kind": "passives", "id": "phoenix_feather",
                        "subject": "one long fiery phoenix feather glowing red, orange and gold, curling at its tip, a few small "
                                   "embers rising off it"},
    "skedaddle": {"set": "48", "kind": "passives", "id": "skedaddle",
                  "subject": "a brown leather cowboy boot with a silver spur in mid-stride, kicking up a small puff of dust, three "
                             "bold red speed lines streaming out behind it"},
    "powder_keg": {"set": "48", "kind": "passives", "id": "powder_keg",
                   "subject": "a small round dark wooden powder keg with black iron hoops, a short lit fuse sparking bright yellow "
                              "at its top"},
    "loose_change": {"set": "48", "kind": "passives", "id": "loose_change",
                     "subject": "three shiny gold coins tumbling out of a torn brown leather trouser pocket, one coin in mid-air"},
    "gas_mask": {"set": "48", "screen": "blue", "kind": "passives", "id": "gas_mask",
                 "subject": "an old dark grey rubber gas mask seen from the front with two round amber glass eye lenses, a round "
                            "steel filter canister at its mouth and brown leather straps, a wisp of sickly green poison smoke "
                            "curling round it"},
    "hot_streak": {"set": "48", "kind": "passives", "id": "hot_streak",
                   "subject": "a pair of white dice both showing six, wreathed in bright orange and red flames"},
    "steady_hand_a": {"set": "48", "kind": "passives", "id": "steady_hand",
                      "subject": "a single silver revolver lying perfectly level on a small wooden stand, pointing to the right, a "
                                 "thin straight red aiming line from its barrel, no hands"},
    "steady_hand_b": {"set": "48", "kind": "passives", "id": "steady_hand",
                      "subject": "a round red and white bullseye target with one single bullet hole dead in its centre, a thin "
                                 "wisp of smoke rising from the hole"},
    "trick_shot2": {"set": "48", "kind": "mutations", "id": "trick_shot",
                    "subject": "a golden bullet flying along a path that zig-zags in two sharp ricochets, a small white impact "
                               "star at each bend of the path"},
    "birdshot_lane": {"set": "48", "kind": "mutations", "id": "birdshot_lane",
                      "subject": "a wide flat band of many small round lead pellets flying side by side in a straight rectangular "
                                 "spread towards the upper right, short motion streaks behind them"},
    "methanol": {"set": "48", "kind": "mutations", "id": "methanol",
                 "subject": "a glass bottle of clear pale blue alcohol, a rag stuffed in its neck burning with a bright blue flame"},
    "big_peas": {"set": "48", "screen": "blue", "kind": "mutations", "id": "big_peas",
                 "subject": "one huge round bright green pea with a bold white highlight next to two tiny green peas"},
    "bouncing_skull": {"set": "48", "kind": "mutations", "id": "bouncing_skull",
                       "subject": "a bone-white skull bouncing along in two arcs, small dust puffs where it touched the ground, a "
                                  "dotted arc line showing its path"},
    "curare": {"set": "48", "screen": "blue", "kind": "mutations", "id": "curare",
               "subject": "a thin blowgun dart with red feather fletching whose sharp tip drips thick dark green poison, one dark "
                          "green drop falling from the tip"},
    "mini_crits": {"set": "48", "kind": "mutations", "id": "mini_crits",
                   "subject": "a brass bullet pointing to the upper right with three small bright yellow sparkle stars bursting "
                              "from its tip"},
    "repulsor": {"set": "48", "kind": "mutations", "id": "repulsor",
                 "subject": "a glowing purple shockwave ring bursting outwards, three small dark rocks flying away from its "
                            "centre, crackling purple energy arcs"},
    "tinnitus": {"set": "48", "kind": "mutations", "id": "tinnitus",
                 "subject": "a cartoon ear with three curved ringing sound waves beside it and a small yellow starburst"},
    "silver_bullet": {"set": "48", "kind": "mutations", "id": "silver_bullet",
                      "subject": "a gleaming polished silver bullet pointing to the upper right with a pale blue glint and a soft "
                                 "blue glow round it"},
    "hip_shot": {"set": "48", "kind": "mutations", "id": "hip_shot",
                 "subject": "a silver revolver spinning in mid-air with a circular motion arc round it and a puff of smoke at "
                            "its muzzle"},
    "thors_wrath": {"set": "48", "kind": "mutations", "id": "thors_wrath",
                    "subject": "a heavy grey stone war hammer with crackling bright blue lightning bolts arcing off its head"},
    "giant_slayer": {"set": "48", "kind": "mutations", "id": "giant_slayer",
                     "subject": "a heavy war hammer smashing down onto a golden crown, the crown cracked and dented, a white "
                                "impact star"},
    "pollen": {"set": "48", "screen": "blue", "kind": "mutations", "id": "pollen",
               "subject": "a bright pink desert flower in full bloom with a yellow centre, golden pollen grains floating up from "
                          "it, a short green stem"},
    "tarantula_hawk": {"set": "48", "kind": "mutations", "id": "tarantula_hawk",
                       "subject": "a big menacing wasp with a glossy dark purple-black body, bright orange wings and a long "
                                  "stinger, seen from above at an angle"},
    "wide_reach": {"set": "48", "screen": "blue", "kind": "mutations", "id": "wide_reach",
                   "subject": "a round olive-green land mine with a red button on top leaping up into the air on a coiled steel "
                              "spring, curved motion lines below it"},
    "extra_supply": {"set": "48", "screen": "blue", "kind": "mutations", "id": "extra_supply",
                     "subject": "two round olive-green land mines with red buttons stacked one on the other, a bold yellow plus "
                                "sign beside them"},
    "new_equipment": {"set": "48", "screen": "blue", "kind": "mutations", "id": "new_equipment",
                      "subject": "a big shiny brand-new olive-green hand grenade with a gleaming steel lever and pull ring, a "
                                 "small white sparkle star on it and a little paper price tag tied to the ring"},
    "blunderbuss": {"set": "48", "kind": "evolutions", "id": "blunderbuss",
                    "subject": "an old blunderbuss gun with a wide flared bell-shaped brass muzzle and a polished dark wooden "
                               "stock with gold trim, a cone of fiery pellets bursting from the muzzle"},
    "moonshine": {"set": "48", "kind": "evolutions", "id": "moonshine",
                  "subject": "a stoneware moonshine jug marked with three black crosses, its open top burning with a tall bright "
                             "blue flame, blue embers floating round it"},
    "pea_cannon": {"set": "48", "screen": "blue", "kind": "evolutions", "id": "pea_cannon",
                   "subject": "a big pea pod with golden leaves shaped like a cannon with a wide barrel, firing one huge "
                              "glowing green pea"},
    "grave_hail": {"set": "48", "screen": "blue", "kind": "evolutions", "id": "grave_hail",
                   "subject": "three bone-white skulls falling from above trailing green poison smoke, one bouncing off the "
                              "ground with a puff of dust"},
    "hive_queen": {"set": "48", "kind": "evolutions", "id": "hive_queen",
                   "subject": "a big golden honeycomb beehive with a small gold crown on top, purple and orange wasps buzzing "
                              "round it"},
    "jackrabbit_mines": {"set": "48", "screen": "blue", "kind": "evolutions", "id": "jackrabbit_mines",
                         "subject": "a round olive-green land mine with two long brown jackrabbit ears sticking up from it, "
                                    "leaping high into the air on a coiled steel spring"},
    "golden_pineapple": {"set": "48", "kind": "evolutions", "id": "golden_pineapple",
                         "subject": "a golden pineapple hand grenade with a gleaming gold segmented body, a gold lever and a gold "
                                    "pull ring, a few white sparkles"},
    # the first try bent the bullet itself into a zig-zag: the path is a dotted line, the bullet small at its end
    "trick_shot3": {"set": "48", "kind": "mutations", "id": "trick_shot",
                    "subject": "a bold dotted white line that zig-zags across the picture from the lower left to the upper right, "
                               "bending sharply twice, a small white impact star at each bend, and one small straight golden bullet "
                               "at its upper right end flying on along the line"},
    # the first jugs carried plus signs (read as healing): a plain jug, the blue flame is the idea
    "moonshine2": {"set": "48", "kind": "evolutions", "id": "moonshine",
                   "subject": "a round brown stoneware moonshine jug with a small loop handle and no markings at all, its open top "
                              "burning with a tall bright blue flame, a few blue embers floating round it"},
    # Reach moved to uncommon (pass 48): its green crosshair sank into the green plate
    "reach2": {"set": "48", "kind": "passives", "id": "reach",
               "subject": "a bright golden-orange target of three concentric rings with a thin crosshair, four small bold arrows "
                          "pointing outwards from the outer ring"},
    "pollen_poppy": {"set": "48", "screen": "blue", "kind": "pickups", "id": "pollen_poppy",
                     "subject": "a single bright red desert poppy flower on a short green stem with two small leaves, seen from "
                                "the side and a little above"},
    "pollen_marigold": {"set": "48", "screen": "blue", "kind": "pickups", "id": "pollen_marigold",
                        "subject": "a single bright yellow desert marigold flower with many petals on a short green stem with two "
                                   "small leaves, seen from the side and a little above"},
    "pollen_lupine": {"set": "48", "screen": "blue", "kind": "pickups", "id": "pollen_lupine",
                      "subject": "a single tall spike of small violet lupine flowers on a green stem with a few hand-shaped "
                                 "leaves at its foot, seen from the side"},
    # pass 49 (Garry's seventh list): five icons redone (Barrel Rush a barrel wearing the Sprint power-up's logo, the Gas
    # Mask without its fumes, Brimstone Brand a real branding iron, Hot Streak's dice as true cubes from a Blender render,
    # Skedaddle's spur on the heel) and the Hornet Nest turned Killer Bees (its icon and Second Sting's)
    "barrel_rush3": {"set": "49", "kind": "passives", "id": "barrel_rush", "ref": "sprint_logo_ref.png",
                     "subject": "The reference image is a logo: a pair of light blue sneakers with small white feathered wings. Paint "
                                "one sturdy wooden barrel standing upright, seen from the front and a little above, warm brown wooden "
                                "staves held by two dark iron hoops, and on its front between the hoops that exact logo painted big "
                                "and clear on the wood: the two light blue sneakers with their white wings. Only the barrel and its "
                                "logo, no speed lines, no motion lines, no splinters, no boot"},
    "gas_mask2": {"set": "49", "screen": "blue", "kind": "passives", "id": "gas_mask",
                  "subject": "an old dark grey rubber gas mask seen from the front with two round amber glass eye lenses, a round "
                             "steel filter canister at its mouth and brown leather straps at its sides. Only the mask: no smoke, no "
                             "fumes, no gas, no cloud, no wisps, nothing around it"},
    "brimstone_brand2": {"set": "49", "kind": "passives", "id": "brimstone_brand",
                         "subject": "a cattle branding iron lying diagonally from the lower left to the upper right: a worn wooden "
                                    "handle at the lower left, a long straight black iron rod, and at the upper right end the brand: "
                                    "a flat iron symbol of a horned devil's skull glowing red-hot orange and yellow, a thin curl of "
                                    "smoke and a few sparks rising off the hot symbol"},
    "brimstone_brand3": {"set": "49", "kind": "passives", "id": "brimstone_brand",
                         "subject": "a cattle branding iron lying diagonally from the lower left to the upper right: a worn wooden "
                                    "handle at the lower left, a long straight black iron rod, and at the upper right end the brand: "
                                    "a flat iron outline of a single bold flame glowing red-hot orange and yellow, a thin curl of smoke "
                                    "rising off the hot symbol"},
    "hot_streak2": {"set": "49", "kind": "passives", "id": "hot_streak", "ref": "dice_ref.png",
                    "subject": COPY + "two white six-sided dice with rounded edges and round black pips, perfect cubes with "
                               "straight edges and square faces, the front die showing six pips in two neat rows of three, the pips "
                               "evenly spaced, wreathed in bright orange and red flames rising behind them"},
    "skedaddle2": {"set": "49", "kind": "passives", "id": "skedaddle",
                   "subject": "a brown leather cowboy boot in mid-stride with its toe pointing to the right, seen from the side: "
                              "the silver star-shaped spur wheel is fixed at the back of the heel, on the left side of the boot, "
                              "nothing on the toe; three bold red speed lines stream out to the left behind the heel, a small puff of "
                              "dust under the heel"},
    "killer_bees": {"set": "49", "kind": "weapons", "id": "hornet_nest",
                    "subject": "a wild honeybee hive: slabs of golden honeycomb hanging from a short branch, dripping a little honey, "
                               "with three angry fuzzy killer bees, golden brown with black stripes, small clear wings and frowning red "
                               "eyes, flying out of it"},
    "second_sting2": {"set": "49", "kind": "mutations", "id": "second_sting",
                      "subject": "one angry fuzzy killer bee, golden brown with black stripes and small clear wings, its stinger "
                                 "pointed forward, flying in a tight loop: a curved white motion line loops round behind it"},
    # the Killer Bees' icon to match its new model (lane B: a cartoon hive of stacked rings, the comb slabs read as blades)
    "killer_bees2": {"set": "49", "kind": "weapons", "id": "hornet_nest",
                     "subject": "a cartoon beehive made of stacked rounded honey-gold rings, wider in the middle, with a dark round door "
                                "near its bottom and a drop of honey under it, hanging from a short brown branch with two green leaves, "
                                "three angry fuzzy killer bees, golden brown with black stripes, small clear wings and frowning red eyes, "
                                "flying round it"},
    "hive_queen2": {"set": "49", "kind": "evolutions", "id": "hive_queen",
                    "subject": "a big cartoon beehive of stacked rounded shining gold rings with a dark round door, a small gold crown "
                               "with a red jewel sitting on its top, a fat queen bee with a tiny crown peeking out of the door, two "
                               "angry fuzzy killer bees flying round it, a soft golden glow"},
    # Brimstone Brand again: the first two read as a sceptre and a torch; a branding iron's brand is a flat shape bent from
    # thin iron bars, and the mark it burns says what it is
    "brimstone_brand4": {"set": "49", "kind": "passives", "id": "brimstone_brand",
                         "subject": "a cowboy's branding iron lying diagonally from the lower left to the upper right: a long thin black "
                                    "iron rod with a round ring for a handle at the lower left, and at the upper right end the brand, a "
                                    "flat symbol bent from thin iron bars like wire, a simple outline of a devil's head with two horns, "
                                    "glowing red-hot orange and yellow, not a solid head, a few small sparks round it"},
    "brimstone_brand5": {"set": "49", "kind": "passives", "id": "brimstone_brand",
                         "subject": "a cowboy's branding iron pressed down onto a light wooden plank: a long thin black iron rod coming "
                                    "in from the upper right, its brand at the bottom a flat symbol bent from thin iron bars, the outline "
                                    "of a devil's head with two horns glowing red-hot orange, and beside it on the plank the same horned "
                                    "symbol already burned in black, a curl of smoke rising from it"},
    # pass 60 (Garry: "Critical Thinking - also regenerate that icon, it's nonsensical"; the set-53 one was a bare blade with
    # a yellow dot): two concepts, four seeds each, picked by eye at HUD size. 2 = precise hits (a sabre's point dead in a
    # bullseye), 3 = the pun (thinking + a critical hit: a lightbulb run through by the blade)
    "critical_thinking2": {"set": "60", "kind": "mutations", "id": "critical_thinking",
                           "subject": "a curved steel cavalry sabre with a brass guard pointing straight up, and floating at its tip a "
                                      "round red-and-white bullseye target with three rings, the sabre's point touching the exact "
                                      "centre of the bullseye with a small bright yellow starburst where it meets"},
    "critical_thinking3": {"set": "60", "kind": "mutations", "id": "critical_thinking",
                           "subject": "a glowing yellow lightbulb with a grey screw base, a curved steel sabre blade run right through "
                                      "it from the lower left to the upper right, the blade's point sticking out of the top of the "
                                      "bulb with a small bright yellow starburst where it exits"},
}


def _ref(name, blue=False):
    """The render laid on the screen colour (Blender renders with a transparent film)."""
    im = Image.open(os.path.join(DL, name)).convert("RGBA")
    g = Image.new("RGBA", im.size, (0, 0, 255, 255) if blue else (0, 255, 0, 255))
    g.alpha_composite(im)
    return comfy.upload_pil(g.convert("RGB"), name)


def paint(only, seeds, dev):
    for key, job in JOBS.items():
        if job is None or (only and key not in only):
            continue
        OUT = _out(job)
        os.makedirs(OUT, exist_ok=True)
        # a subject with green in it (the guitar's sides, poison, a green heart) goes on the blue screen, or the keyer eats it
        blue = job.get("screen") == "blue"
        refs = [_ref(job["ref"], blue)] if job.get("ref") else []
        prompt = job["subject"] + ". " + job.get("style", ga.ICON_STYLE) + ". " + (ga.BG_BLUE if blue else ga.BG_GREEN) + "."
        base = ga.seed_for("icon46_" + key)
        tiles = []
        for k in range(seeds):
            p = os.path.join(OUT, "%s_c%d.png" % (key, k))
            if not os.path.exists(p):
                s = base + k * 7919
                if dev:
                    g = comfy.flux2_dev(prompt, s, 1024, 1024, refs=refs, steps=28, turbo=False, prefix="88fits/icons46_" + key)
                else:
                    g = comfy.klein(prompt, s, 1024, 1024, refs=refs, prefix="88fits/icons46_" + key)
                imgs, secs = comfy.run(g)
                if dev:
                    comfy.release_models()
                Image.open(io.BytesIO(imgs[0])).convert("RGB").save(p)
                json.dump({"seed": s, "prompt": prompt, "refs": refs}, open(p[:-4] + ".json", "w", encoding="utf-8"), indent=1)
                print("  %s c%d seed %d %.0fs" % (key, k, s, secs), flush=True)
            tiles.append(Image.open(p).convert("RGB"))
        sheet = Image.new("RGB", (384 * len(tiles), 412), (30, 30, 36))
        dr = ImageDraw.Draw(sheet)
        for k, t in enumerate(tiles):
            sheet.paste(t.resize((384, 384)), (384 * k, 28))
            dr.text((384 * k + 8, 6), "%s c%d" % (key, k), fill=(255, 255, 255))
        sheet.save(os.path.join(OUT, "review_%s.png" % key))
        print("review", key, flush=True)


def _halo(img, color, blur):
    a = img.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", img.size, color + (0,))
    layer.putalpha(grown.point(lambda v: int(v * 0.6)))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(layer)
    out.alpha_composite(img)
    return out


def pick(pairs):
    for pair in pairs:
        key, n = pair.split("=")
        job = JOBS[key]
        img = Image.open(os.path.join(_out(job), "%s_c%s.png" % (key, n))).convert("RGB")
        if job["kind"] == "badge":
            cell, _ = ga.finish(img, 128, 0.8, False, None, 0.035, None, (24, 14, 20, 255))
            dst = os.path.join(REPO, "game", "art", "ui", "badges", job["id"] + ".png")
            _halo(cell, job["halo"], 4).save(dst)
        elif job["kind"] == "source":
            icon, _ = ga.finish(img, 256, 0.92, False, None, 0.006)
            dst = os.path.join(REPO, "game", "art", "ui", "sources", job["id"] + ".png")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            icon.save(dst)
        elif job["kind"] == "ui":
            icon, _ = ga.finish(img, 256, 0.92, False, None, 0.012, None, (36, 27, 20, 255))
            dst = os.path.join(REPO, "game", "art", "ui", "wanted", job["id"] + ".png")
            icon.save(dst)
        else:
            folder = os.path.join(CONTENT, job["kind"], job["id"])
            if not os.path.isdir(folder):
                print("  no folder yet for", key, "->", folder)
                continue
            icon, _ = ga.finish(img, 256, 0.92, False, None, 0.006)
            dst = os.path.join(folder, job["id"] + "_icon.png")
            if os.path.exists(dst):
                bk = os.path.join(DL, "backup", "icons" + str(job.get("set", "46")))
                os.makedirs(bk, exist_ok=True)
                Image.open(dst).save(os.path.join(bk, job["id"] + "_icon.png"))
            icon.save(dst)
        print("installed", key, "candidate", n, "->", dst)


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--pick" in a:
        pick(a[a.index("--pick") + 1:])
    else:
        only = a[a.index("--only") + 1].split(",") if "--only" in a else None
        seeds = int(a[a.index("--seeds") + 1]) if "--seeds" in a else 4
        paint(only, seeds, "--dev" in a)
