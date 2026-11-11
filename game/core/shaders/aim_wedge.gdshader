// The aim wedge (pass 136, lane GUNS; R7 of docs/weapons_aim): a faint wedge on the sand in front of the Outlaw and a
// small chevron at his feet (core/systems/AimWedge.gd). The mesh is built flat in the node's own space (forward -Z) and
// placed by the node; here every vertex is laid on the terrain from the map's height grid (the same lookup as
// ground_mark.gdshader: Telegraphs._ground_uniforms fills the uniforms). UV.x the distance from him in metres (-1 on the
// chevron), UV.y the angle off the facing (radians). The fill is a soft dark shade (a white one vanished on Sundown's
// pale sand) between WEDGE_FROM and WEDGE_TO, fading in near him and out at the far end; its two edges thin pale lines,
// the chevron pale; a shot's line (ray_angle) flashes pale down it for a moment. Transparent and unshaded: drawn after
// the stage filter, so it reads the same on every stage.
//
// Pass 139 (lane AIM; Garry: "Now that we have a kind of a attack direction indicator, let's go ahead and try to use that
// to indicate when dragon's breath and big mouth will attack next"): the tell. `kind` 0, the wedge's fan, also draws the
// Dragon's Breath's band (b_*): its own cone from b_from to its reach, outlined faintly, filling from his feet towards
// its far end as the cooldown runs (a bright front where the fill has got to), full and breathing while it is ready,
// a flash as it breathes, then draining as the breath runs out. `kind` 1 is the Big Mouth's line (m_*), a strip of its
// own laid down the beam's line from the mouth (UV.x 0..1 along its reach, UV.y -0.5..0.5 across m_width): a dashed
// line to its full reach, a solid line filling along it as the cooldown runs, full and pulsing while it is ready,
// brighter and wider with dashes racing out through the wind-up, a flash as the beam leaves, draining while it pours.
// The states (AimWedge.TELL_*): 0 charging, 1 ready, 2 winding up, 3 firing.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords, fog_disabled;

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float lift = 0.1;
// 0 the wedge's fan (with the Breath's band), 1 the Mouth's line
uniform int kind = 0;
// the fill's shade and its alpha at its fullest; the edge lines' and the chevron's colour and alpha
uniform vec3 fill_tint : source_color = vec3(0.13, 0.09, 0.06);
uniform float alpha = 0.12;
uniform vec3 line_tint : source_color = vec3(1.0, 0.95, 0.82);
uniform float line_alpha = 0.32;
uniform float chevron_alpha = 0.5;
// the wedge's own span (metres from his feet) and half its angle (radians), for its fade and edge lines
uniform float wedge_from = 0.9;
uniform float wedge_to = 3.0;
uniform float half_angle = 0.5236;
// 1 at rest, more during a pulse
uniform float strength = 1.0;
// a shot's line: its angle off the facing and how bright it is now (0: none)
uniform float ray_angle = 0.0;
uniform float ray_strength = 0.0;

// the Breath's band (kind 0): on, its span, half its angle, the charge (0..1; while firing the share of the breath left),
// its state, colour, the flash (1 as it breathes, falling to 0), the ready beat (0..1)
uniform float b_on = 0.0;
uniform float b_from = 0.45;
uniform float b_reach = 5.0;
uniform float b_half = 0.4363;
uniform float b_charge = 0.0;
uniform int b_state = 0;
uniform vec3 b_color : source_color = vec3(1.0, 0.56, 0.16);
// its deep shade (AimWedge: the colour more saturated and darker), for the fill and the outline: a pale fill vanished on
// Sundown's sand
uniform vec3 b_deep : source_color = vec3(0.85, 0.36, 0.0);
uniform float b_flash = 0.0;
uniform float b_beat = 0.0;
// the band's alphas: the outline, the fill charging (near .. at its front), ready (low .. high beat), the front's line
uniform float b_line_a = 0.5;
uniform float b_fill_lo = 0.1;
uniform float b_fill_hi = 0.26;
uniform float b_ready_lo = 0.26;
uniform float b_ready_hi = 0.4;
uniform float b_front_a = 0.9;

// the Mouth's line (kind 1): its reach and the strip's width (metres), the charge, state, colour, flash, ready beat,
// how far into the wind-up (0..1) and a clock (seconds) for the dashes racing out
uniform float m_reach = 13.0;
uniform float m_width = 0.9;
uniform float m_charge = 0.0;
uniform int m_state = 0;
uniform vec3 m_color : source_color = vec3(1.0, 0.25, 0.7);
uniform float m_flash = 0.0;
uniform float m_beat = 0.0;
uniform float m_wind = 0.0;
uniform float m_clock = 0.0;
// pass 143: the line's share of its opacity (AimWedge.MOUTH_GAIN: half as noticeable as pass 139's)
uniform float m_gain = 1.0;

float ground(vec2 p) {
	if (grid_n < 2) {
		return 0.0;
	}
	float top = float(grid_n - 1) - 0.001;
	float fx = clamp((p.x + half_size) * resolution, 0.0, top);
	float fz = clamp((p.y + half_size) * resolution, 0.0, top);
	int ix = int(fx);
	int iz = int(fz);
	float tx = fx - float(ix);
	float tz = fz - float(iz);
	float h00 = texelFetch(heights, ivec2(ix, iz), 0).r;
	float h10 = texelFetch(heights, ivec2(ix + 1, iz), 0).r;
	float h01 = texelFetch(heights, ivec2(ix, iz + 1), 0).r;
	float h11 = texelFetch(heights, ivec2(ix + 1, iz + 1), 0).r;
	return mix(mix(h00, h10, tx), mix(h01, h11, tx), tz);
}

void vertex() {
	VERTEX.y = ground(VERTEX.xz) + lift;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

// `top` (rgb, a) laid over `under`
vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	vec3 c = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / max(a, 0.0001);
	return vec4(c, a);
}

// the wedge itself: the dark shade between its two pale edge lines, and a shot's line flashing down it
vec4 wedge(float r, float ang) {
	float to_edge = (half_angle - abs(ang)) * r;
	if (to_edge < 0.0) {
		return vec4(0.0);
	}
	float fr = (r - wedge_from) / max(wedge_to - wedge_from, 0.01);
	// in over the first 20%, out over the last 45% (as the pass 136 mesh's vertex alphas)
	float va = smoothstep(0.0, 0.2, fr) * (1.0 - smoothstep(0.55, 1.0, fr));
	float fill_a = alpha * va * strength;
	// the edge lines, about 5 cm wide
	float line_a = line_alpha * va * (1.0 - smoothstep(0.025, 0.07, to_edge)) * (0.6 + 0.4 * strength);
	float ray_a = 0.0;
	if (ray_strength > 0.0) {
		// a line about 0.14 m wide down the shot's way, fading towards the wedge's far end
		float off = abs(ang - ray_angle) * max(r, 0.3);
		ray_a = ray_strength * exp(-(off * off) / 0.005) * clamp(1.0 - r / (wedge_to + 0.4), 0.0, 1.0) * step(wedge_from, r);
	}
	float la = clamp(line_a + ray_a, 0.0, 1.0);
	vec3 c = mix(fill_tint, line_tint, la / max(la + fill_a, 0.0001));
	return vec4(c, clamp(fill_a + la, 0.0, 1.0));
}

// the Breath's band: its cone from b_from to b_reach
vec4 breath_band(float r, float ang) {
	float to_side = (b_half - abs(ang)) * r;
	float to_far = b_reach - r;
	if (to_side < -0.03 || to_far < -0.03 || r < b_from) {
		return vec4(0.0);
	}
	float span = max(b_reach - b_from, 0.1);
	float along = clamp((r - b_from) / span, 0.0, 1.0);
	// in softly over its first 40 cm
	float near = smoothstep(b_from, b_from + 0.4, r);
	float edge = min(to_side, to_far);
	float inside = step(0.0, edge);
	// the outline: its two sides and its far arc, about 5 cm, always there so its reach shows
	float line_k = (1.0 - smoothstep(0.02, 0.06, abs(edge))) * near;
	float line_a = b_line_a * line_k;
	float fill_a = 0.0;
	float front_a = 0.0;
	if (b_state == 1 || b_state == 2) {
		// ready: full and breathing, the outline brighter
		fill_a = mix(b_ready_lo, b_ready_hi, b_beat) * inside * near;
		line_a = (b_line_a + 0.25 + 0.15 * b_beat) * line_k;
	} else if (b_state == 3) {
		// breathing: what is left of the breath, from his feet out
		fill_a = b_fill_lo * inside * near * step(along, b_charge);
		line_a *= 0.6;
	} else {
		// charging: the fill grows from his feet to the far end, denser at its front, a bright front line
		float f = max(b_charge, 0.0001);
		fill_a = mix(b_fill_lo, b_fill_hi, clamp(along / f, 0.0, 1.0)) * inside * near * step(along, b_charge);
		float fr = b_from + span * b_charge;
		front_a = b_front_a * exp(-((r - fr) * (r - fr)) / 0.004) * inside * near * step(0.02, b_charge);
	}
	fill_a += b_flash * 0.45 * inside * near;
	float la = clamp(line_a + front_a, 0.0, 1.0);
	vec3 fill_c = b_deep;
	// the outline darker still; the front bright, towards white
	vec3 line_c = mix(b_deep * 0.75, mix(b_color, vec3(1.0, 0.97, 0.9), 0.35), front_a / max(line_a + front_a, 0.0001));
	vec3 c = mix(fill_c, line_c, la / max(la + fill_a, 0.0001));
	c = mix(c, vec3(1.0, 0.97, 0.9), clamp(b_flash * 0.6, 0.0, 1.0));
	return vec4(c, clamp(fill_a + la, 0.0, 1.0));
}

// the Mouth's line along its strip: `s` metres along, `x` metres across from its middle
vec4 mouth_line(float s, float x) {
	float ends = smoothstep(0.0, 0.5, s) * (1.0 - smoothstep(m_reach - 0.5, m_reach, s));
	float wide = 1.0 + 0.6 * m_wind;
	// a core about 16 cm across and a glow about half a metre (thinner vanished at the game's zoom)
	float core = exp(-(x * x) / (0.0065 * wide * wide));
	float glow = exp(-(x * x) / (0.045 * wide * wide));
	float fill = m_charge * m_reach;
	// a dashed line to the full reach: 0.45 m dashes 0.75 m apart
	float dash = step(fract(s / 0.75), 0.6);
	float core_a = 0.38 * dash * core;
	float glow_a = 0.0;
	if (m_state == 1) {
		// ready: solid and pulsing
		core_a = (0.75 + 0.2 * m_beat) * core;
		glow_a = (0.2 + 0.12 * m_beat) * glow;
	} else if (m_state == 2) {
		// winding up: brighter and wider, bright dashes racing out down the line
		float race = smoothstep(0.55, 1.0, sin((s - m_clock * 9.0) * 3.0) * 0.5 + 0.5);
		core_a = (0.85 + 0.15 * m_wind) * core + 0.3 * race * core;
		glow_a = (0.28 + 0.2 * m_wind) * glow + 0.15 * race * glow;
	} else if (m_state == 3) {
		// pouring: what is left of the pour
		float lit = step(s, fill);
		core_a = mix(core_a, 0.7 * core, lit);
		glow_a = 0.2 * glow * lit;
	} else {
		// charging: solid up to the charge, a bright tick across at its front
		float lit = step(s, fill);
		core_a = mix(core_a, 0.68 * core, lit);
		glow_a = 0.14 * glow * lit;
		float tick = exp(-((s - fill) * (s - fill)) / 0.008) * (1.0 - smoothstep(0.22, 0.32, abs(x))) * step(0.02, m_charge);
		core_a += 0.85 * tick;
	}
	core_a += m_flash * 0.5 * core;
	glow_a += m_flash * 0.35 * glow;
	float a = clamp((core_a + glow_a) * ends, 0.0, 1.0) * m_gain;
	// the core hot towards white, the glow the colour's deep shade (a pale glow vanished on Sundown's sand)
	vec3 hot = mix(m_color, vec3(1.0, 0.97, 0.95), 0.3 + 0.5 * m_flash);
	vec3 c = mix(m_color * 0.8, hot, core_a / max(core_a + glow_a, 0.0001));
	return vec4(c, a);
}

void fragment() {
	if (kind == 1) {
		vec4 m = mouth_line(UV.x * m_reach, UV.y * m_width);
		ALBEDO = m.rgb;
		ALPHA = m.a;
	} else if (UV.x < 0.0) {
		ALBEDO = line_tint;
		ALPHA = clamp(chevron_alpha * (0.7 + 0.3 * strength), 0.0, 1.0);
	} else {
		vec4 c = wedge(UV.x, UV.y);
		if (b_on > 0.5) {
			c = over(breath_band(UV.x, UV.y), c);
		}
		if (c.a <= 0.002) {
			discard;
		}
		ALBEDO = c.rgb;
		ALPHA = c.a;
	}
}
