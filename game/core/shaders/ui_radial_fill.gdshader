// The Royale item frame (pass 122, lane UIKIT_B; design_handoff_88fits_royale README section 3): one canvas shader that
// paints a whole frame into a Control's rect (draw_rect in white, UV 0..1 over it, `size` the rect in px), back to front:
//   a soft glow outside the frame (epic, legendary, evolved), the navy base straight down (`base_px`), the navy outline
//   (`edge_px`), the rarity rim (`rim_px`: a vertical gradient from `rim_a` at the top to `rim_b` at the foot; mode 1 the
//   legendary's four-stop gold bevel rim_a / rim_b / rim_c / rim_d at 0 / .35 / .72 / 1; mode 2 the evolved rainbow,
//   a conic sweep of `rainbow[8]` clockwise from the top), a dark line just inside the rim (`inner_px`, the legendary's
//   7a4a05), and the face: a radial fill lit at `center` (the mock's circle at 50 % 42 %), `light` there, `base` at
//   `base_at` of the reach, `dark` at the farthest corner, with a white lip `lip_px` tall at the top (lip_alpha .35) and
//   a dark foot (`foot_px`, foot_alpha .22). `shape` 1 is a disc (a hero's badge, the coin). `pad` px of the rect on
//   every side are left for the glow; `alpha` fades the lot (the HUD's see-through slots). Every edge is anti-aliased
//   over a pixel by a signed distance, so the frame reads at 56 px as at 320. WPlate drives it; WCoin uses the disc.
//   Review fix (lane UIKIT_B_FIX): the glow is cut where a neighbour's frame stands (`cuts[cut_count]`: centre x, centre
//   y in this rect's px, the half side, how solid it is; a rounded box of `cut_radius` with its `cut_base` below), so a
//   row's glows all sit behind their neighbours instead of over the earlier one and under the later one.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 size = vec2(100.0, 100.0);
uniform float pad = 0.0;
uniform float base_px = 8.0;
uniform float radius = 6.0;
uniform int shape = 0;
uniform float edge_px = 4.0;
uniform vec4 edge_color : source_color = vec4(0.055, 0.122, 0.29, 1.0);
uniform float rim_px = 7.0;
uniform int rim_mode = 0;
uniform vec4 rim_a : source_color = vec4(0.894, 0.914, 0.933, 1.0);
uniform vec4 rim_b : source_color = vec4(0.584, 0.631, 0.69, 1.0);
uniform vec4 rim_c : source_color = vec4(0.769, 0.49, 0.039, 1.0);
uniform vec4 rim_d : source_color = vec4(1.0, 0.886, 0.541, 1.0);
uniform vec4 rainbow[8] : source_color;
uniform float inner_px = 0.0;
uniform vec4 inner_color : source_color = vec4(0.478, 0.29, 0.02, 1.0);
uniform float face_radius = 2.0;
uniform vec4 light : source_color = vec4(0.804, 0.835, 0.871, 1.0);
uniform vec4 base : source_color = vec4(0.584, 0.631, 0.69, 1.0);
uniform vec4 dark : source_color = vec4(0.404, 0.447, 0.498, 1.0);
uniform vec2 center = vec2(0.5, 0.42);
uniform float base_at = 0.55;
uniform float lip_px = 6.0;
uniform float lip_alpha = 0.35;
uniform float foot_px = 6.0;
uniform float foot_alpha = 0.22;
uniform float glow_px = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float alpha = 1.0;
uniform int cut_count = 0;
uniform vec4 cuts[6];
uniform float cut_radius = 6.0;
uniform float cut_base = 8.0;

// The signed distance (px) from `p` to a box of half-size `h` with `r` corners, centred on the origin.
float sd_box(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// The same for this frame's own shape: a disc when the shape asks for one.
float sd(vec2 p, vec2 h, float r) {
	if (shape == 1) {
		return length(p) - min(h.x, h.y);
	}
	return sd_box(p, h, r);
}

// 1 inside the edge at distance d, 0 outside, a pixel of anti-aliasing across it.
float inside(float d) {
	return 1.0 - smoothstep(-0.5, 0.5, d);
}

void fragment() {
	vec2 px = UV * size;
	vec2 fsize = size - vec2(2.0 * pad, 2.0 * pad + base_px);
	vec2 c = vec2(pad) + fsize * 0.5;
	vec2 p = px - c;
	vec2 half = fsize * 0.5;
	float d_out = sd(p, half, radius);
	float d_base = sd(p - vec2(0.0, base_px), half, radius);
	float d_rim = sd(p, half - vec2(edge_px), max(radius - edge_px, 0.0));
	float d_face = sd(p, half - vec2(edge_px + rim_px), face_radius);
	float d_inner = sd(p, half - vec2(edge_px + rim_px + inner_px), max(face_radius - inner_px, 0.0));
	vec4 col = vec4(0.0);
	// the glow: outside the outline, fading over glow_px with a soft tail
	if (glow_px > 0.0 && glow_color.a > 0.0) {
		float g = 1.0 - smoothstep(0.0, glow_px, max(d_out, 0.0));
		// nothing where an earlier neighbour's frame (and its base) stands
		for (int i = 0; i < cut_count; i++) {
			vec2 cp = px - cuts[i].xy;
			vec2 ch = vec2(cuts[i].z);
			float dc = min(sd_box(cp, ch, cut_radius), sd_box(cp - vec2(0.0, cut_base), ch, cut_radius));
			g *= 1.0 - inside(dc) * cuts[i].w;
		}
		col = vec4(glow_color.rgb, glow_color.a * g * g);
	}
	// the base straight down, then the outline box over it
	col = mix(col, edge_color, inside(d_base));
	col = mix(col, edge_color, inside(d_out));
	// the rim
	float in_rim = inside(d_rim);
	if (rim_px > 0.0) {
		vec4 rimc;
		if (rim_mode == 2) {
			float a = atan(p.x, -p.y);
			float t = fract(a / 6.2831853);
			float seg = t * 7.0;
			int k = int(floor(seg));
			rimc = mix(rainbow[k], rainbow[min(k + 1, 7)], fract(seg));
		} else {
			float t = clamp((p.y + half.y) / max(fsize.y, 1.0), 0.0, 1.0);
			if (rim_mode == 1) {
				if (t < 0.35) {
					rimc = mix(rim_a, rim_b, t / 0.35);
				} else if (t < 0.72) {
					rimc = mix(rim_b, rim_c, (t - 0.35) / 0.37);
				} else {
					rimc = mix(rim_c, rim_d, (t - 0.72) / 0.28);
				}
			} else {
				rimc = mix(rim_a, rim_b, t);
			}
		}
		col = mix(col, rimc, in_rim);
	}
	// the face: the radial fill, its lip and its foot
	float in_face = inside(d_face);
	if (in_face > 0.0) {
		vec2 fhalf = half - vec2(edge_px + rim_px);
		vec2 fp = p + fhalf;
		vec2 fs = fhalf * 2.0;
		vec2 lit = center * fs;
		vec2 corner = max(lit, fs - lit);
		float reach = max(length(corner), 1.0);
		float u = clamp(length(fp - lit) / reach, 0.0, 1.0);
		vec4 face = u < base_at ? mix(light, base, u / max(base_at, 0.001)) : mix(base, dark, (u - base_at) / max(1.0 - base_at, 0.001));
		float lip = 1.0 - smoothstep(lip_px - 0.5, lip_px + 0.5, fp.y);
		face.rgb = mix(face.rgb, vec3(1.0), lip * lip_alpha);
		float foot = smoothstep(fs.y - foot_px - 0.5, fs.y - foot_px + 0.5, fp.y);
		face.rgb = mix(face.rgb, vec3(0.0), foot * foot_alpha);
		col = mix(col, face, in_face);
		if (inner_px > 0.0) {
			float line = in_face * (1.0 - inside(d_inner));
			col = mix(col, inner_color, line);
		}
	}
	col.a *= alpha;
	COLOR = col * COLOR;
}
