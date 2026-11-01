## The first scene: the loading screen. Pass 58 made it (Garry, 2026-10-07: "for like a second or 2 right before the Main
## Menu loads I see a kind of a broken version of our Loading screen ... maybe add a loading progress bar"); pass 118
## (lane LOAD) remade it. Garry: "No icon, No progress bar. Title Drop sequence at the start and an animation of
## silhuettes of revolvers, stars, bombs, boots and other western(y) and not so western(y) item silhouettes that read
## well. They are meant to look like strips of saloon wallpaper and each strip moves slowly up-and a bit to the right,
## down-and a bit to the right ... This is meant to be the new progress bar replacement showing that the game is loading."
##
## Godot's boot splash is the plain paper now (application/boot_splash/show_image off: the engine draws only bg_color,
## W.PAPER), and on Android the system splash is the same paper with a transparent icon (tools/make_splash.py). This
## scene's first frame is that paper too, on any screen, so the hand-over from the engine cannot be seen. Then:
##   - the saloon wallpaper fades in from the paper (FADE_IN): vertical strips side by side in two tones with a pinstripe
##     between them, each carrying a tone-on-tone print of silhouettes (the strip atlas, art/ui/loading/wallpaper.png,
##     tools/make_loading_wallpaper.py); strip 1 scrolls slowly up, strip 2 down, strip 3 up ..., and the whole set
##     drifts slowly to the right (it wraps). The motion is the loading indicator: it never stops while the game loads.
##   - the game's name slams in on its plate (art/ui/loading/title_plate.png, set like the title screen's logo). Pass 119
##     (lane LOADUI; Garry: "The title drop style sucks. Make something more action game like, less bouncy and stuff")
##     replaced pass 118's drop, squash and bounce with an action game's title slam, no bounce at all: the plate punches
##     in from PUNCH_FROM times its size to its own in PUNCH, faster and faster, zoom-blurred, with speed lines closing in
##     on it, and stops dead: a white impact flash held for HITSTOP (the hit-stop), then a short screen shake, a shockwave
##     ring bending the wallpaper, dust and chips knocked off its edges, a thud (ui_stamp) over a low boom, and a brass
##     glint sweeping across the letters. The other entrance tried ("split": OUTLAW from the left, SURVIVORS from the
##     right, locking together) is kept behind `entrance` for the captures (tools/dl/p119/LOADUI/).
##   - the title screen loads on a thread meanwhile (ResourceLoader.load_threaded_request). It is built (its _ready: the
##     live title builds Red Canyon there, a frame of a few hundred ms) only once the slam has settled (the glint and the
##     chips done), so that frame never freezes it half way, and it draws once under this screen; then this screen
##     dissolves into it, never before MIN_SHOW of its own clock, even when the load was done sooner.
##
## Everything this screen shows is one opaque draw: one shader over one full-screen rect paints the wallpaper, the speed
## lines, the ring, the dust, the plate, the chips and the flash (two textures, no node per silhouette or chip; the shake
## moves the whole picture inside the shader). A fade takes the same share of every pixel only when each pixel is drawn
## once (pass 58's review: layered draws showed through each other during the dissolve).
##
## The screen's clock counts each frame at most MAX_STEP, so a long frame (the engine's start in the first one, the
## title's build, its first draw) pauses the motion instead of throwing it forward; the first frame does not count at
## all, so it is the plain paper whatever its length.
##
## The camera cutout's ink band (CutoutBand) waits while this screen shows (the boot splash cannot draw it, so it would
## pop in over the paper) and fades in with the title.
##
## Pass 120 (lane STARTGO): the same screen plays between a tap on Start and the run (ui/RunCurtain.gd extends this one:
## its drawing, its slam and its threaded load, with a revolver's cylinder seen end-on cut out of ink round them). The one
## draw carries that cylinder too (the iris_* uniforms, cylinder_sd); at the app's start it is off (iris_mode 0) and this
## screen draws exactly what it did. The hooks a curtain changes: _hold_band, _report_content, _may_build, _place_scene,
## _report, fail_line.
extends Control

const TITLE := "res://ui/TitleScreen.tscn"
const WALLPAPER := "res://art/ui/loading/wallpaper.png"
const PLATE := "res://art/ui/loading/title_plate.png"

## The atlas's layout, in canvas px (tools/make_loading_wallpaper.py writes these lines): each strip STRIP_W wide, its
## print repeating every PERIOD, VARIANTS strips of different motif orders side by side in the texture.
const STRIP_W := 180.0
const PERIOD := 1440.0
const VARIANTS := 4
## The plate's picture in canvas px (its hard shadow and a clear margin included) and its shadow's offset.
const PLATE_SIZE := Vector2(930.0, 312.7)
const PLATE_SHADOW := 14.0

## The wallpaper's motion, canvas px a second: each strip's scroll (up, down, up ...) and the set's drift to the right.
const SCROLL := 46.0
const DRIFT := 15.0
## The strips' lean (degrees; 0 = upright). Captures with a lean are in tools/dl/p118/LOAD/; upright read better.
const TILT_DEG := 0.0
## The most strips the screen can show at once, a lean included (the shader's strip_y array).
const MAX_STRIPS := 12

## The sequence (s on the screen's clock; pass 119, lane LOADUI): the wallpaper fades in from the paper, then at SLAM_AT
## the plate slams in and stops dead at its rest (never past it, never back: no squash, no bounce).
const FADE_IN := 0.3
const SLAM_AT := 0.3
## The entrance: "punch" (the plate from PUNCH_FROM times its size to its own in PUNCH s, faster and faster: s = F -
## (F - 1) u^2) or "split" (OUTLAW, the rows above PLATE_CUT, from off the left edge and SURVIVORS from off the right in
## SLIDE s at one speed, locking together). Captures of both: tools/dl/p119/LOADUI/punch_v2, split_v2. The punch read
## stronger: the name is legible from its first frame and it lands as one hit; the split's halves are smeared bars
## until the last frame.
const ENTRANCE := "punch"
const PUNCH := 0.12
const PUNCH_FROM := 2.6
## The share of PUNCH over which the plate comes in from clear (it is huge and pale first, solid well before the hit).
const PUNCH_FADE := 0.35
const SLIDE := 0.13
## Where the split cuts the plate's picture (a share of its height: the clear paper between OUTLAW's brass shadow, 0.60,
## and SURVIVORS, 0.68).
const PLATE_CUT := 0.64
## The motion blur's shutter (s): the plate is drawn smeared from where it was this long before to where it is.
const BLUR_LAG := 0.025
## The speed lines: full while the plate comes in, gone LINES_OUT s after the hit.
const LINES_OUT := 0.12
## The hit (s after the plate stops): the white flash held at FLASH for HITSTOP (the hit-stop: nothing else moves yet),
## then fading (e^(-t / FLASH_TAU)); the plate takes only PLATE_FLASH of it, so it stands dark on the white (an impact
## frame).
const HITSTOP := 0.05
const FLASH := 0.85
const FLASH_TAU := 0.035
const PLATE_FLASH := 0.25
## After the hit-stop: the screen shakes SHAKE s, SHAKE_PX at first, falling as (1 - k)^2; a shockwave ring runs out
## RING_PX from the plate's edge in RING s; dust and chips fly DUST and DEBRIS s (CHIPS of them, from its edges).
const SHAKE := 0.3
const SHAKE_PX := 22.0
const RING := 0.42
const RING_PX := 900.0
const DUST := 0.5
const DEBRIS := 0.55
const CHIPS := 26
## The brass glint: GLINT_AT s after the hit it sweeps across the plate, left to right, in GLINT s.
const GLINT_AT := 0.18
const GLINT := 0.38
## Where the plate's middle rests, as a share of the screen's height (a little above the middle reads as the middle).
const REST_Y := 0.46
## The earliest the dissolve may start (s on the screen's clock): the slam has settled and been seen for a moment.
const MIN_SHOW := 1.15

## The longest frame the screen's clock counts (s). The first frame carries the engine's start (Godot's frame clock
## starts before the autoloads load), the title's build and its first draw each hold a frame; counted whole they would
## throw the drop or eat the dissolve (pass 58: on a slow phone the dissolve came close to a cut).
const MAX_STEP := 1.0 / 30.0
## The dissolve into the title (s, sine in and out).
const DISSOLVE := 0.25
## How long the title's threaded load may sit still (in progress, its progress not moving) before this screen stops
## waiting for it and loads the title at once (s).
const STALL := 10.0
## What the screen says on a paper card under the plate when nothing could bring the title up.
const FAIL_LINE := "The title screen did not load. Please close the game and start it again."

## The thud as the plate hits: the first of these the sound map binds (pass 118's), and under it a low boom for weight
## (pass 119: the stamp alone is a bright 0.1 s click; the grenade's boom, BOOM_DB quieter, is the map's deepest short hit).
const THUD := ["ui_stamp", "ui_chest_knock"]
const BOOM := ["w_lob_boom"]
const BOOM_DB := -8.0

## The one draw (every point moved by `shake` first, so the whole picture shakes). The wallpaper: each canvas px is turned
## by the lean about the screen's middle, moved left by the drift, and falls in a strip (index = floor(x / STRIP_W)); the
## strip's own vertical shift comes from strip_y (indexed from first_strip, set each frame from Boot.gd, which decides who
## goes up and who down); the atlas's masks are coloured with the strip's ground (two tones, alternating) and mixed in
## from the paper by `fade`; the shockwave ring bends and lights it. Then, behind the plate: the speed lines (radial,
## closing in, for the punch; rush lines over and under it for the split) and the dust round its edges. Then the plate (its
## middle at plate_mid, scaled about it; smeared over its last BLUR_LAG of motion; the glint across it), the chips in
## front of it, and the flash over everything.
const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D wallpaper : filter_linear, repeat_enable;
uniform sampler2D plate : filter_linear, repeat_disable;
uniform vec2 canvas = vec2(1080.0, 1920.0);
uniform float strip_w = 180.0;
uniform float period = 1440.0;
uniform float variants = 4.0;
uniform float drift = 0.0;
uniform float first_strip = 0.0;
uniform float strip_y[12];
uniform float tilt = 0.0;
uniform float fade = 0.0;
uniform vec4 paper = vec4(1.0);
uniform vec4 ground_a = vec4(1.0);
uniform vec4 ground_b = vec4(1.0);
uniform vec4 motif_color = vec4(0.0);
uniform vec4 accent_color = vec4(0.0);
uniform vec4 line_color = vec4(0.0);
uniform float vignette = 0.0;
uniform vec4 vignette_color = vec4(0.0);
uniform vec2 shake = vec2(0.0);
uniform float plate_on = 0.0;
uniform float plate_alpha = 1.0;
uniform vec2 plate_mid = vec2(0.0);
uniform vec2 plate_size = vec2(1.0);
uniform float entrance = 0.0;
uniform float cut = 0.64;
uniform float plate_scale = 1.0;
uniform float scale_prev = 1.0;
uniform float split_off = 0.0;
uniform float split_prev = 0.0;
uniform float speed = 0.0;
uniform vec4 speed_color = vec4(0.0);
uniform float hit_t = -1.0;
uniform float hitstop = 0.05;
uniform float flash = 0.0;
uniform float plate_flash = 0.55;
uniform vec4 flash_color = vec4(1.0);
uniform float ring_life = 0.42;
uniform float ring_px = 900.0;
uniform float dust_life = 0.5;
uniform vec4 dust_color = vec4(1.0);
uniform float debris_life = 0.55;
uniform int chips = 26;
uniform vec4 chip_ink = vec4(0.0);
uniform vec4 chip_brass = vec4(1.0);
uniform vec4 chip_paper = vec4(1.0);
uniform float glint_t = -1.0;
uniform vec4 glint_color = vec4(1.0);
// pass 120 (lane STARTGO): the revolver's cylinder seen end-on, a cut-out in ink (RunCurtain.gd). iris_mode: 0 off (the
// app's start), 1 the wipe (ink round it, the screen under seen through it), 2 the reveal (ink round it, this screen
// through it), 3 the open (this screen round it, the run under seen through it). iris_shape: the chambers' distance and
// radius, the flutes' distance and radius, as shares of the cylinder's radius iris_r.
uniform int iris_mode = 0;
uniform vec2 iris_mid = vec2(540.0, 960.0);
uniform float iris_r = 0.0;
uniform float iris_turn = 0.0;
uniform float iris_chamber = 1.0;
uniform float iris_pin = 1.0;
uniform float iris_shade = 0.0;
uniform vec4 iris_ink = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 iris_shape = vec4(0.58, 0.24, 1.03, 0.15);
uniform float iris_pin_r = 0.08;
uniform float iris_border = 0.0;

varying vec2 pos;

void vertex() {
	pos = VERTEX;
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

vec3 wall_at(vec2 q0) {
	vec2 mid = canvas * 0.5;
	vec2 q = q0 - mid;
	float cs = cos(tilt);
	float sn = sin(tilt);
	vec2 p = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y) + mid;
	float x = p.x - drift;
	float idx = floor(x / strip_w);
	int slot = clamp(int(idx - first_strip), 0, 11);
	float lx = clamp(x - idx * strip_w, 0.0, strip_w);
	float y = p.y - strip_y[slot];
	float v = mod(idx, variants);
	vec2 uv = vec2((v * strip_w + lx) / (variants * strip_w), fract(y / period));
	vec3 m = texture(wallpaper, uv).rgb;
	vec3 col = mod(idx, 2.0) < 0.5 ? ground_a.rgb : ground_b.rgb;
	col = mix(col, motif_color.rgb, m.r);
	col = mix(col, accent_color.rgb, m.g);
	col = mix(col, line_color.rgb, m.b);
	return col;
}

// the plate's picture at p (premultiplied): its middle at plate_mid + off, scaled by sc about it, only its rows lo..hi
vec4 plate_px(vec2 p, float sc, vec2 off, float lo, float hi) {
	vec2 uv = ((p - plate_mid - off) / sc + plate_size * 0.5) / plate_size;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < lo || uv.y >= hi) {
		return vec4(0.0);
	}
	vec4 c = texture(plate, uv);
	return vec4(c.rgb * c.a, c.a);
}

// a point on the plate's edge (u: 0..1 round it, clockwise from its top left corner, about its middle) and the way out
vec4 edge_at(float u) {
	vec2 hs = plate_size * vec2(0.5, 0.42);
	float per = 4.0 * (hs.x + hs.y);
	float s = fract(u) * per;
	if (s < 2.0 * hs.x) {
		return vec4(-hs.x + s, -hs.y, 0.0, -1.0);
	}
	s -= 2.0 * hs.x;
	if (s < 2.0 * hs.y) {
		return vec4(hs.x, -hs.y + s, 1.0, 0.0);
	}
	s -= 2.0 * hs.y;
	if (s < 2.0 * hs.x) {
		return vec4(hs.x - s, hs.y, 0.0, 1.0);
	}
	s -= 2.0 * hs.x;
	return vec4(-hs.x, hs.y - s, -1.0, 0.0);
}

// the cylinder as signed distances (px; below 0 inside its metal, the cut-out): x the whole shape, y its rim alone (the
// round with its flutes, for the shade). A round of radius iris_r turned by iris_turn, six flutes cut into its rim between
// six chambers, and the pin's hole in its middle; a shut chamber or pin (size 0) is 1.5 px under nothing, so it leaves no
// pixel. The angle is folded into the 30 degrees between a chamber and the next flute, so one chamber and one flute are
// measured (RunCurtain.cylinder_sd is the same in GDScript).
vec2 cylinder_sd(vec2 at) {
	float R = max(iris_r, 0.0001);
	vec2 q = at - iris_mid;
	float r = length(q);
	float a = r > 0.001 ? atan(q.y, q.x) - iris_turn : 0.0;
	float sector = 1.0471976;
	a = abs(mod(a + sector * 0.5, sector) - sector * 0.5);
	vec2 f = vec2(cos(a), sin(a)) * r;
	// shut (radius 0): nothing is metal, not even its middle
	float body = iris_r > 0.0 ? r - R : 1.0e5;
	float chamber = length(f - vec2(iris_shape.x * R, 0.0)) - (iris_shape.y * R * iris_chamber - 1.5);
	float flute = length(f - vec2(0.8660254, 0.5) * iris_shape.z * R) - iris_shape.w * R;
	float pin = r - (iris_pin_r * R * iris_pin - 1.5);
	float rim = max(body, -flute);
	return vec2(max(rim, max(-chamber, -pin)), rim);
}

// this screen at canvas px `at`: the wallpaper, the slam and the plate (the one draw before pass 120's cylinder)
vec3 loading_screen(vec2 at) {
	vec2 p = at - shake;
	vec2 mid = canvas * 0.5;
	vec2 d = p - plate_mid;
	float r = length(d);
	float after = hit_t - hitstop;
	// the shockwave: a ring running out from the plate, bending the wallpaper under it and lighting it
	float ring = 0.0;
	vec2 wp = p;
	if (hit_t >= 0.0 && after >= 0.0 && after < ring_life) {
		float rk = after / ring_life;
		vec2 e = d / (plate_size * vec2(0.5, 0.5));
		float er = length(e * vec2(1.0, 0.62));
		float rad = 1.0 + ring_px / (plate_size.x * 0.5) * (1.0 - pow(1.0 - rk, 2.4));
		float w = mix(0.16, 0.05, rk);
		ring = exp(-pow((er - rad) / w, 2.0)) * (1.0 - rk);
		wp -= (r > 0.001 ? d / r : vec2(0.0)) * ring * 30.0;
	}
	vec3 col = wall_at(wp);
	float rv = length((p - mid) / mid);
	col = mix(col, vignette_color.rgb, vignette * smoothstep(0.55, 1.35, rv));
	col = mix(paper.rgb, col, fade);
	col = mix(col, flash_color.rgb, ring * 0.5);
	// the speed lines
	if (speed > 0.0) {
		float ln = 0.0;
		if (entrance < 0.5) {
			float a = atan(d.y, d.x) / 6.2831853 + 0.5;
			float n = 84.0;
			float cell = floor(a * n);
			float f = fract(a * n);
			float hw = 0.05 + 0.15 * hash(cell * 1.7 + 9.0);
			float inner = length(plate_size) * 0.5 * plate_scale * (0.75 + 0.6 * hash(cell * 2.3 + 1.0));
			ln = step(0.4, hash(cell + 3.0)) * (1.0 - smoothstep(hw * 0.55, hw, abs(f - 0.5)))
				* smoothstep(inner, inner + 140.0, r);
		} else {
			// rush lines across the screen in the bands over and under the plate, each running its way
			float row = floor(p.y / 12.0);
			float fy = abs(fract(p.y / 12.0) - 0.5) * 12.0;
			float top = plate_mid.y - plate_size.y * 0.5;
			float bot = top + plate_size.y;
			float band = step(top - 360.0, p.y) * step(p.y, top) + step(bot, p.y) * step(p.y, bot + 360.0);
			float len = 0.25 + 0.5 * hash(row * 1.3 + 2.0);
			float run = fract(p.x / canvas.x * 0.5 + hash(row * 2.9 + 4.0) + (p.y < plate_mid.y ? -1.0 : 1.0) * split_off / canvas.x);
			ln = step(0.45, hash(row + 5.0)) * (1.0 - smoothstep(1.0, 2.4, fy)) * band * step(run, len);
		}
		col = mix(col, speed_color.rgb, clamp(ln, 0.0, 1.0) * speed);
	}
	// the dust knocked out from under the plate's edges, rolling out and thinning (no puff reaches 380 px past them)
	if (hit_t >= 0.0 && after >= 0.0 && after < dust_life
			&& abs(d.x) < plate_size.x * 0.5 + 380.0 && abs(d.y) < plate_size.y * 0.5 + 380.0) {
		float k = after / dust_life;
		float go = 1.0 - exp(-after * 7.0);
		float clear = 1.0;
		for (int i = 0; i < 20; i++) {
			float fi = float(i);
			float h = hash(fi + 1.0);
			float h2 = hash(fi * 3.7 + 2.0);
			vec4 e = edge_at((fi + 0.8 * h) / 20.0 + 0.013);
			vec2 c = plate_mid + e.xy + e.zw * (30.0 + 210.0 * h2) * go;
			float rad = (26.0 + 22.0 * h) * (0.7 + 1.5 * k);
			float a = pow(1.0 - k, 1.3) * 0.6;
			clear *= 1.0 - a * (1.0 - smoothstep(0.25, 1.0, length(p - c) / rad));
		}
		col = mix(col, dust_color.rgb, 1.0 - clear);
	}
	// the hit's flash on everything behind the plate
	col = mix(col, flash_color.rgb, flash);
	// the plate
	if (plate_on > 0.5) {
		vec4 acc = vec4(0.0);
		int n = 1;
		// a sample's place along the smear is jittered per pixel, so the copies blend into a blur instead of stepping
		float jit = hash(dot(floor(at), vec2(1.0, 157.0)) * 0.013);
		if (entrance < 0.5) {
			n = abs(scale_prev - plate_scale) > 0.0005 ? 16 : 1;
			for (int i = 0; i < n; i++) {
				float f = n > 1 ? (float(i) + jit) / float(n) : 0.0;
				acc += plate_px(p, mix(plate_scale, scale_prev, f), vec2(0.0), 0.0, 2.0);
			}
		} else {
			n = abs(split_prev - split_off) > 0.05 ? 16 : 1;
			for (int i = 0; i < n; i++) {
				float f = n > 1 ? (float(i) + jit) / float(n) : 0.0;
				float o = mix(split_off, split_prev, f);
				acc += plate_px(p, 1.0, vec2(-o, 0.0), 0.0, cut);
				acc += plate_px(p, 1.0, vec2(o, 0.0), cut, 2.0);
			}
		}
		acc = acc / float(n) * plate_alpha;
		if (acc.a > 0.0) {
			vec3 pc = acc.rgb / acc.a;
			// the glint: a band of light sweeping across, leaning right, brightest on the ink and brass of the letters
			if (glint_t >= 0.0 && glint_t <= 1.0) {
				float xs = d.x + d.y * 0.55;
				float b = mix(-plate_size.x * 0.5 - 260.0, plate_size.x * 0.5 + 260.0, glint_t);
				float band = exp(-pow((xs - b) / 46.0, 2.0)) + 0.35 * exp(-pow((xs - b + 70.0) / 22.0, 2.0));
				float lum = dot(pc, vec3(0.3, 0.59, 0.11));
				float ink = 1.0 - smoothstep(0.3, 0.75, lum);
				pc = mix(pc, glint_color.rgb, clamp(band * (0.2 + 0.75 * ink), 0.0, 1.0));
			}
			col = col * (1.0 - acc.a) + pc * acc.a;
		}
	}
	// the chips knocked off the plate's edges: flying out, spinning, falling, in front of it
	if (hit_t >= 0.0 && after >= 0.0 && after < debris_life) {
		float k = after / debris_life;
		float fade_c = 1.0 - smoothstep(0.6, 1.0, k);
		for (int i = 0; i < chips; i++) {
			float fi = float(i);
			float h = hash(fi * 5.1 + 11.0);
			float h2 = hash(fi * 2.3 + 7.0);
			float h3 = hash(fi * 7.9 + 3.0);
			vec4 e = edge_at((fi + 0.7 * h) / float(chips) + 0.37);
			if (entrance > 0.5) {
				// the split: they burst from the joint's two ends
				float side = mod(fi, 2.0) < 0.5 ? -1.0 : 1.0;
				e = vec4(side * plate_size.x * 0.5, plate_size.y * (cut - 0.5), side, (h2 - 0.6) * 1.6);
			}
			vec2 tang = vec2(-e.w, e.z);
			vec2 vel = e.zw * (620.0 + 900.0 * h2) + tang * (h3 - 0.5) * 560.0 + vec2(0.0, -300.0 * h);
			vec2 c = plate_mid + e.xy + vel * after + vec2(0.0, 0.5 * 2600.0 * after * after);
			float ang = h * 6.2831853 + (h2 - 0.5) * 34.0 * after;
			vec2 q = p - c;
			if (abs(q.x) > 30.0 || abs(q.y) > 30.0) {
				continue;
			}
			vec2 l = vec2(cos(ang) * q.x + sin(ang) * q.y, -sin(ang) * q.x + cos(ang) * q.y);
			vec2 sz = vec2(8.0 + 13.0 * h3, 3.0 + 4.0 * h2);
			float edge = max(abs(l.x) - sz.x, abs(l.y) - sz.y);
			float outer = 1.0 - smoothstep(-0.8, 0.8, edge);
			if (outer > 0.0) {
				vec3 cc = h3 < 0.45 ? chip_ink.rgb : (h3 < 0.75 ? chip_brass.rgb : chip_paper.rgb);
				float inner = 1.0 - smoothstep(-0.8, 0.8, edge + 2.0);
				col = mix(col, chip_ink.rgb, outer * fade_c);
				col = mix(col, cc, inner * fade_c);
			}
		}
	}
	// and the flash over all of it (the plate keeps its shape through it)
	col = mix(col, flash_color.rgb, flash * plate_flash);
	return col;
}

void fragment() {
	vec3 col = iris_ink.rgb;
	float a = 1.0;
	// the cylinder's cut-out (im 1 inside its metal, smoothed over one screen pixel at any size) and an ink shade inside
	// its edges, as a hole's rim (ish)
	float im = 0.0;
	float ish = 0.0;
	float sdx = 1.0;
	float w = 1.0;
	if (iris_mode > 0) {
		vec2 sd = cylinder_sd(pos);
		sdx = sd.x;
		w = max(fwidth(sd.x), 0.0001);
		im = clamp(0.5 - sd.x / w, 0.0, 1.0);
		ish = iris_shade * exp(-max(-sd.y, 0.0) / (iris_r * 0.06 + 1.5));
	}
	if (iris_mode == 1) {
		a = (1.0 - im) + im * ish;
	} else {
		col = loading_screen(pos);
		if (iris_mode == 2) {
			col = mix(iris_ink.rgb, col, im * (1.0 - ish));
		} else if (iris_mode == 3) {
			// an ink line iris_border wide round the cut-out on this screen's side, so it reads over any run
			float ob = clamp(0.5 - (sdx - iris_border) / w, 0.0, 1.0) * (1.0 - im);
			col = mix(col, iris_ink.rgb, ob);
			a = (1.0 - im) + im * ish;
			col = ((1.0 - im) * col + im * ish * iris_ink.rgb) / max(a, 0.0001);
		}
	}
	COLOR = vec4(col, a) * COLOR;
}
"""

signal handed_over(title: Node)
## The threaded load failed or stalled; the title is loaded at once straight after (tests mend a broken scene here).
signal load_failed(why: String)

## Where the title goes: null puts it under the root as the current scene (the game); a node takes it as a child and
## the current scene is left alone (tests).
var host: Node = null
## The title once it is built (tests, captures).
var title: Node = null
## Where the title is loaded from (tests point it at scenes of their own).
var title_path := TITLE
## STALL for this screen (tests).
var stall_limit := STALL
## FAIL_LINE for this screen (a curtain says its own).
var fail_line := FAIL_LINE
## The title could not be loaded at all: the screen says so under the plate, its wallpaper stops (it never waits
## silently, and never moves as if it were still loading).
var failed := false
## What happened when, in order, on the screen's clock: [name, s] ("fade_in", "landed" (the plate's hit), "settled" (the
## slam's last chip and glint done), "loaded", "built", "first_frame", "dissolve") (tests: the plate lands before the
## dissolve; captures).
var events: Array = []
## Which entrance plays: ENTRANCE, or "split" (the captures; pass 119 tried both).
var entrance := ENTRANCE
## Where the time went, in ms: "engine" (from the process start to this scene: the engine and the autoloads), "load"
## (the title's threaded load), "build" (its instancing and _ready), "first_frame" (its first frame, under this screen).
var timings := {}

var _wall: ColorRect
var _mat: ShaderMaterial
var _band: CanvasLayer
var _loading := false
var _t_load := 0
var _clock := 0.0        # the screen's own clock (s)
var _frames := 0
var _scene: PackedScene = null   # loaded, waiting for the plate to settle
var _handing := false
var _thud_done := false
var _progress := -1.0    # the threaded load's last progress, and how long it has sat still (s)
var _still := 0.0
var _dissolve_t := -1.0  # the dissolve, 0..1 (below 0: not started)
var _canvas := Vector2(1080, 1920)


func _ready() -> void:
	# pass 114 (lane REPLAY): a replay's process (tools/replay.py: `-- replay=<file>`) opens the replay viewer, never the
	# title; a prod build never does (and carries no viewer: export filter replay/*)
	if _open_replay():
		return
	timings["engine"] = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	get_viewport().size_changed.connect(_place)
	_place()
	_hold_band()
	_report_content()
	if not ResourceLoader.exists(title_path):
		print("Boot: no title screen at %s; registry loaded %d weapons" % [title_path, Registry.weapons.size()])
		_fail()
		return
	_t_load = Time.get_ticks_usec()
	if _request() != OK:
		_recover("the threaded request was refused", false)
		return
	_loading = true


## The cutout's band waits while this screen shows (a curtain over a screen leaves it alone: ui/RunCurtain.gd).
func _hold_band() -> void:
	_band = get_node_or_null("/root/CutoutBand") as CanvasLayer
	if _band:
		_band.visible = false


## The content's problems, said once at the app's start.
func _report_content() -> void:
	if not Registry.problems.is_empty():
		for p in Registry.problems:
			push_warning("Content: " + str(p))


const REPLAY_VIEWER := "res://replay/ReplayViewer.gd"


func _open_replay() -> bool:
	if Settings.is_prod():
		return false
	var want := false
	for a in OS.get_cmdline_user_args():
		if str(a).trim_prefix("--").begins_with("replay="):
			want = true
	if not want or not ResourceLoader.exists(REPLAY_VIEWER):
		return false
	var script = load(REPLAY_VIEWER)
	if script == null:
		return false
	var v: Control = script.new()
	v.name = "ReplayViewer"
	get_tree().root.add_child.call_deferred(v)
	(func() -> void:
		get_tree().current_scene = v
		queue_free()).call_deferred()
	return true


## The one draw: a rect over the whole screen (over the paper ColorRect of Boot.tscn) with the shader and its two
## pictures, coloured from the kit's tokens (make_loading_wallpaper.py's palette() mirrors these mixes for its mock).
func _build() -> void:
	_wall = ColorRect.new()
	_wall.name = "Wallpaper"
	_wall.color = Color.WHITE
	_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_wall)
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("wallpaper", load(WALLPAPER) as Texture2D if ResourceLoader.exists(WALLPAPER) else null)
	_mat.set_shader_parameter("plate", load(PLATE) as Texture2D if ResourceLoader.exists(PLATE) else null)
	_mat.set_shader_parameter("strip_w", STRIP_W)
	_mat.set_shader_parameter("period", PERIOD)
	_mat.set_shader_parameter("variants", float(VARIANTS))
	_mat.set_shader_parameter("tilt", deg_to_rad(TILT_DEG))
	_mat.set_shader_parameter("plate_size", PLATE_SIZE)
	_mat.set_shader_parameter("cut", PLATE_CUT)
	_mat.set_shader_parameter("hitstop", HITSTOP)
	_mat.set_shader_parameter("plate_flash", PLATE_FLASH)
	_mat.set_shader_parameter("ring_life", RING)
	_mat.set_shader_parameter("ring_px", RING_PX)
	_mat.set_shader_parameter("dust_life", DUST)
	_mat.set_shader_parameter("debris_life", DEBRIS)
	_mat.set_shader_parameter("chips", CHIPS)
	for k in PALETTE:
		_mat.set_shader_parameter(k, palette(k))
	_mat.set_shader_parameter("vignette", VIGNETTE)
	_wall.material = _mat
	_apply()


## The wallpaper's colours: the paper it fades in from, the two grounds of the strips, the print, the fillers and beads,
## the pinstripe, the vignette's warm shade and the dust, each a mix of two of the kit's tokens (W.gd); pass 119 adds the
## slam's: the speed lines (ink), the flash (a warm white), the chips (ink, brass and paper) and the glint (a pale brass).
const PALETTE := ["paper", "ground_a", "ground_b", "motif_color", "accent_color", "line_color", "vignette_color",
	"dust_color", "speed_color", "flash_color", "chip_ink", "chip_brass", "chip_paper", "glint_color"]
const VIGNETTE := 0.35


static func palette(key: String) -> Color:
	match key:
		"paper", "ground_a":
			return W.PAPER
		"ground_b":
			return W.PAPER.lerp(W.AGED, 0.55)
		"motif_color":
			return W.PAPER.lerp(W.ROCK, 0.26)
		"accent_color":
			return W.PAPER.lerp(W.ROCK, 0.2)
		"line_color":
			return W.PAPER.lerp(W.INK_SOFT, 0.4)
		"vignette_color":
			return W.PAPER.lerp(W.ROCK, 0.3).lerp(W.INK, 0.12)
		"dust_color":
			return W.AGED.lerp(W.ROCK, 0.3)
		"speed_color":
			return W.PAPER.lerp(W.INK, 0.55)
		"flash_color":
			return Color.WHITE.lerp(W.PAPER, 0.25)
		"chip_ink":
			return W.INK
		"chip_brass":
			return W.BRASS
		"chip_paper":
			return W.PAPER
		"glint_color":
			return W.BRASS.lerp(Color.WHITE, 0.62)
	return W.PAPER


## Whether the wallpaper's atlas is there to draw (a capture may hand the shader the PNG itself).
func has_wallpaper() -> bool:
	return _mat != null and _mat.get_shader_parameter("wallpaper") != null


func _place() -> void:
	_canvas = get_viewport_rect().size
	if _mat:
		_mat.set_shader_parameter("canvas", _canvas)
		_apply()


func _process(delta: float) -> void:
	# the first frame is the plain paper, the boot splash's own colour, however long it took
	if _frames > 0 and not failed:
		_clock += minf(delta, MAX_STEP)
	_frames += 1
	_apply()
	if _dissolve_t >= 0.0:
		if _step_dissolve(delta):
			queue_free()
		return
	if failed:
		return
	if _loading:
		_watch(delta)
	if _scene != null and not _handing and _may_build():
		_handing = true
		_hand_over(_scene)


## Whether the loaded scene may be built now: once the slam has settled (a curtain may wait a little longer).
func _may_build() -> bool:
	return is_settled()


# ---------------------------------------------------------------- the sequence

## What the screen's clock reads (s; tests, captures).
func clock() -> float:
	return _clock


## The wallpaper's share over the paper, 0..1, at clock t (sine in and out).
static func fade_at(t: float) -> float:
	var k := clampf(t / FADE_IN, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * k)


## Strip `index`'s direction: even strips scroll up (-1), odd ones down (+1).
static func strip_dir(index: int) -> float:
	return -1.0 if posmod(index, 2) == 0 else 1.0


## Strip `index`'s shift down at clock t (canvas px): a phase of its own (so neighbours never line up) plus its scroll.
static func strip_shift(index: int, t: float) -> float:
	return fposmod(index * 0.618034, 1.0) * PERIOD + strip_dir(index) * SCROLL * t


## How long the plate takes to come in (s) for an entrance.
static func approach_time(mode: String) -> float:
	return SLIDE if mode == "split" else PUNCH


## The punch: the plate's scale s seconds after it began, PUNCH_FROM -> 1, faster and faster (F - (F - 1) u^2); exactly 1
## from PUNCH on, never below it (no squash, no bounce).
static func punch_scale(s: float) -> float:
	if s <= 0.0:
		return PUNCH_FROM
	if s >= PUNCH:
		return 1.0
	var u := s / PUNCH
	return PUNCH_FROM - (PUNCH_FROM - 1.0) * u * u


## The punch's opacity: clear as it begins, solid from PUNCH_FADE of the way in.
static func punch_alpha(s: float) -> float:
	return clampf(s / (PUNCH * PUNCH_FADE), 0.0, 1.0)


## The split: how far each half is from its rest s seconds after it began (canvas px): `dist` at first, at one high
## speed (an ease-in kept it off the screen for most of its run), exactly 0 from SLIDE on.
static func split_offset(s: float, dist: float) -> float:
	if s <= 0.0:
		return dist
	if s >= SLIDE:
		return 0.0
	return dist * (1.0 - s / SLIDE)


## The speed lines' strength s seconds after the plate began to come in: full while it comes, gone LINES_OUT after the hit.
static func speed_at(s: float, mode: String) -> float:
	var a := approach_time(mode)
	if s < 0.0:
		return 0.0
	if s < a:
		return 1.0
	return clampf(1.0 - (s - a) / LINES_OUT, 0.0, 1.0)


## The flash h seconds after the hit: FLASH through the hit-stop, then fading as e^(-t / FLASH_TAU); 0 before the hit
## and once it is too faint to see.
static func flash_at(h: float) -> float:
	if h < 0.0:
		return 0.0
	if h < HITSTOP:
		return FLASH
	var f := FLASH * exp(-(h - HITSTOP) / FLASH_TAU)
	return f if f > 0.004 else 0.0


## The whole picture's shake h seconds after the hit (canvas px): still through the hit-stop, then SHAKE_PX falling as
## (1 - k)^2 over SHAKE (two sines of their own on each axis, so it jolts instead of sliding), then still again.
static func shake_at(h: float) -> Vector2:
	var t := h - HITSTOP
	if h < 0.0 or t < 0.0 or t >= SHAKE:
		return Vector2.ZERO
	var k := t / SHAKE
	var amp := SHAKE_PX * (1.0 - k) * (1.0 - k)
	return Vector2(sin(t * 97.0 + 0.6) * 0.8 + sin(t * 151.0 + 2.0) * 0.35,
		sin(t * 113.0 + 1.3) * 0.8 + sin(t * 173.0 + 0.4) * 0.35) * amp


## When the plate hits its rest, on the screen's clock.
func impact_time() -> float:
	return SLAM_AT + approach_time(entrance)


## When the slam is over (the shake, the ring, the dust, the chips and the glint all done), on the screen's clock.
func settle_time() -> float:
	var after := HITSTOP + maxf(maxf(SHAKE, RING), maxf(DUST, DEBRIS))
	return impact_time() + maxf(after, GLINT_AT + GLINT)


## The plate has hit its rest / the slam has settled, on the screen's clock.
func has_landed() -> bool:
	return _clock >= impact_time()


func is_settled() -> bool:
	return _clock >= settle_time()


## Where the plate's middle rests (canvas px): REST_Y of the screen's height.
func plate_rest_mid() -> Vector2:
	return Vector2(_canvas.x * 0.5, roundf(_canvas.y * REST_Y))


## Where the plate's foot rests (canvas px; the failure card goes under it).
func plate_rest_foot() -> Vector2:
	return plate_rest_mid() + Vector2(0.0, PLATE_SIZE.y * 0.5)


## How far off its rest each half of the split starts (canvas px): wholly off the screen.
func split_distance() -> float:
	return _canvas.x * 0.5 + PLATE_SIZE.x * 0.5 + 40.0


## The plate now, Vector3(each half's distance from its rest (px; the split), scale x, scale y) about its middle; at
## rest Vector3(0, 1, 1) (tests, captures).
func plate_pose() -> Vector3:
	var s := _clock - SLAM_AT
	if entrance == "split":
		return Vector3(split_offset(s, split_distance()), 1.0, 1.0)
	var k := punch_scale(s)
	return Vector3(0.0, k, k)


## Every uniform that moves, from the screen's clock.
func _apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("fade", fade_at(_clock))
	# the strips the screen shows: from the leftmost one any corner of the (leaned) screen reaches
	var drift := DRIFT * _clock
	var tilt := deg_to_rad(TILT_DEG)
	var mid := _canvas * 0.5
	var lo := INF
	for c: Vector2 in [Vector2.ZERO, Vector2(_canvas.x, 0.0), Vector2(0.0, _canvas.y), _canvas]:
		var q := c - mid
		lo = minf(lo, cos(tilt) * q.x + sin(tilt) * q.y + mid.x)
	var first := floori((lo - drift) / STRIP_W) - 1
	var ys := PackedFloat32Array()
	ys.resize(MAX_STRIPS)
	for k in MAX_STRIPS:
		ys[k] = strip_shift(first + k, _clock)
	_mat.set_shader_parameter("drift", drift)
	_mat.set_shader_parameter("first_strip", float(first))
	_mat.set_shader_parameter("strip_y", ys)
	# the plate: coming in (smeared over its last BLUR_LAG), then at rest
	var s := _clock - SLAM_AT
	var split := entrance == "split"
	var pose := plate_pose()
	var moving := s >= 0.0 and s < approach_time(entrance)
	_mat.set_shader_parameter("plate_on", 1.0 if s >= 0.0 else 0.0)
	_mat.set_shader_parameter("plate_mid", plate_rest_mid())
	_mat.set_shader_parameter("entrance", 1.0 if split else 0.0)
	_mat.set_shader_parameter("plate_scale", pose.y)
	_mat.set_shader_parameter("split_off", pose.x)
	_mat.set_shader_parameter("scale_prev", punch_scale(s - BLUR_LAG) if moving and not split else pose.y)
	_mat.set_shader_parameter("split_prev", split_offset(s - BLUR_LAG, split_distance()) if moving and split else pose.x)
	_mat.set_shader_parameter("plate_alpha", 1.0 if split else punch_alpha(s))
	_mat.set_shader_parameter("speed", speed_at(s, entrance))
	# the hit: the flash, the shake, the ring, the dust and chips, the glint
	var h := _clock - impact_time()
	_mat.set_shader_parameter("hit_t", h if h >= 0.0 else -1.0)
	_mat.set_shader_parameter("flash", flash_at(h))
	_mat.set_shader_parameter("shake", shake_at(h))
	var g := (h - GLINT_AT) / GLINT
	_mat.set_shader_parameter("glint_t", g if g >= 0.0 and g <= 1.0 else -1.0)
	if h >= 0.0 and not _thud_done:
		_thud_done = true
		_note("landed")
		W.sfx_first(THUD)
		_boom()
	if _clock >= FADE_IN and not _has("fade_in"):
		_note("fade_in")
	if is_settled() and not _has("settled"):
		_note("settled")


## The low boom under the thud, BOOM_DB quieter: the first of BOOM the sound map binds.
func _boom() -> void:
	var a = W.node("Audio")
	if a == null:
		return
	for id: String in BOOM:
		if not (Registry.soundmap.entry(id) as Dictionary).is_empty():
			a.play(id, Vector3.INF, BOOM_DB)
			return


func _note(what: String) -> void:
	events.append([what, _clock])


func _has(what: String) -> bool:
	for e: Array in events:
		if e[0] == what:
			return true
	return false


## When `what` happened on the screen's clock (-1: not yet; tests).
func event_time(what: String) -> float:
	for e: Array in events:
		if e[0] == what:
			return float(e[1])
	return -1.0


# ---------------------------------------------------------------- the load

## The threaded load, once a frame: loaded, the title waits for the plate to settle; failed, or sat still for
## stall_limit, it is loaded at once instead.
func _watch(delta: float) -> void:
	var progress := []
	var status := _status(progress)
	var p := float(progress[0]) if not progress.is_empty() else 0.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			timings["load"] = (Time.get_ticks_usec() - _t_load) / 1000.0
			var scene := ResourceLoader.load_threaded_get(title_path) as PackedScene
			if scene:
				_loaded(scene)
			else:
				_recover("it loaded as nothing", false)
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if p != _progress:
				_progress = p
				_still = 0.0
			else:
				_still += delta
				if _still >= stall_limit:
					_loading = false
					_recover("it sat at %d%% for %.0f s" % [roundi(p * 100.0), _still], false)
		_:
			_loading = false
			_recover("it failed (status %d)" % status, true)


## The threaded request and its status (tests stand in for them to fake a load that never moves).
func _request() -> int:
	return ResourceLoader.load_threaded_request(title_path)


func _status(progress: Array) -> int:
	return ResourceLoader.load_threaded_get_status(title_path, progress)


## The title's scene is in memory: it is built once the plate has settled (_process).
func _loaded(scene: PackedScene) -> void:
	_scene = scene
	_note("loaded")


## The threaded load went wrong: the title is loaded at once, from its file. In Godot 4.7.2 a failed task stays
## registered under its path until it is fetched, and a plain load() or change_scene_to_file() of that path returns
## nothing meanwhile (the old fallback could never bring the title up), so a failed task is fetched first (`release`;
## never a task still in progress: fetching that would wait for it), and the file is read again past the cache and past
## any task on that path (CACHE_MODE_IGNORE). A title that cannot be read even so is said on the screen.
func _recover(why: String, release: bool) -> void:
	push_warning("Boot: the title's threaded load went wrong (%s); loading it at once" % why)
	if release:
		ResourceLoader.load_threaded_get(title_path)
	load_failed.emit(why)
	var scene := ResourceLoader.load(title_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		_fail()
		return
	if not timings.has("load"):
		timings["load"] = (Time.get_ticks_usec() - _t_load) / 1000.0
	_loaded(scene)


## Nothing could bring the title up: the screen stays, its wallpaper stops (the motion means "loading"), and a line on
## a paper card under the plate says so.
func _fail() -> void:
	failed = true
	_loading = false
	push_warning("Boot: the title screen at %s could not be loaded" % title_path)
	if get_node_or_null("Error"):
		return
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 6))
	card.name = "Error"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := W.serif_text(fail_line, 30, W.ROCK,
		600, false, HORIZONTAL_ALIGNMENT_CENTER, 40.0, true, false)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = Vector2(24.0, 18.0)
	line.size = Vector2(_canvas.x - 240.0 - 48.0, 80.0)
	card.add_child(line)
	card.position = Vector2(120.0, plate_rest_foot().y + 60.0)
	card.size = Vector2(_canvas.x - 240.0, 116.0)
	add_child(card)


## The title is loaded and the plate has settled: build the title under this screen, let it draw once, hold until
## MIN_SHOW, then dissolve into it. Each step waits a frame (the build and the first draw each hold one).
func _hand_over(scene: PackedScene) -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	title = scene.instantiate()
	if title.scene_file_path.is_empty():
		# loaded past the cache (_recover): the path a change of scene would have left on it
		title.scene_file_path = title_path
	if host:
		host.add_child(title)
	else:
		_place_scene(title)
	# this screen dissolves into the title: its own fade-in (from the window's clear colour) would show through
	if title is CanvasItem:
		(title as CanvasItem).modulate.a = 1.0
	timings["build"] = (Time.get_ticks_usec() - t0) / 1000.0
	_note("built")
	t0 = Time.get_ticks_usec()
	# the title's first frame (its shaders, the stage's world) is drawn under this screen
	await get_tree().process_frame
	timings["first_frame"] = (Time.get_ticks_usec() - t0) / 1000.0
	_note("first_frame")
	while _clock < MIN_SHOW and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_report()
	_dissolve()
	handed_over.emit(title)


## The built scene under the root as the current scene, this screen over it until it has drawn.
func _place_scene(scene: Node) -> void:
	var root := get_tree().root
	root.add_child(scene)
	root.move_child(self, -1)
	get_tree().current_scene = scene


## Where the time went, once, as the screen begins to leave.
func _report() -> void:
	print("Boot: engine and autoloads %d ms, title loaded in %d ms, built in %d ms, first frame %d ms, dissolve at %.2f s" % [
		int(timings.get("engine", 0)), int(timings.get("load", 0)), int(timings.get("build", 0)),
		int(timings.get("first_frame", 0)), _clock])


## Starts fading this screen away over the title (and the cutout's band in): _process steps it.
func _dissolve() -> void:
	_note("dissolve")
	_set_mouse_ignore(self)
	# the one draw covers the paper rect from here on, so every pixel of this screen is drawn once
	var paper := get_node_or_null("ColorRect") as CanvasItem
	if paper and has_wallpaper():
		paper.visible = false
	if _band:
		_band.visible = true
		for c in _band.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = 0.0
	_dissolve_t = 0.0


## One frame of the dissolve, counting at most MAX_STEP: this screen's cover eases out (sine in and out) and the band
## eases in; true once it is done.
func _step_dissolve(delta: float) -> bool:
	_dissolve_t = minf(_dissolve_t + minf(delta, MAX_STEP) / DISSOLVE, 1.0)
	var k := 0.5 - 0.5 * cos(PI * _dissolve_t)
	modulate.a = 1.0 - k
	if _band and is_instance_valid(_band):
		for c in _band.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = k
	return _dissolve_t >= 1.0


func _set_mouse_ignore(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_set_mouse_ignore(c)


## The band comes back whatever ended this screen.
func _exit_tree() -> void:
	if _band and is_instance_valid(_band):
		_band.visible = true
		for c in _band.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = 1.0
