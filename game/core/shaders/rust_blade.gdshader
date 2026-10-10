// Rust (pass 61, the Orbit Saws' Rust mutation; Garry chose the cheap look: "Oxidised blade tint, rust flakes shed while
// spinning"): the blade's own colour eaten by oxide, drawn unshaded like the material it replaces, on the saws' MultiMesh
// (and the Saw Halo's solid ring). Patches of rust from the flames' noise, read in the blade's own space so they turn
// with it; pitted darker inside the thickest rust; a dark oxidised rim round the edge; a few bright scraped-clean glints
// of the old metal left showing. `amount` is the share of the blade under rust (the Saw Halo keeps more of its gold).
// Pass 64 (Garry: "looks a bit too gruesome"): old orange rust on steel, not raw meat: softer patches (less contrast in
// the noise), pits only in the very thickest rust (PIT_FROM), a fainter rim, and the steel that shows through dull
// (`steel`: a bright white steel between red-orange rust read as marbled meat).
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec4 base_color : source_color = vec4(0.86, 0.88, 0.92, 1.0);
uniform vec4 rust_color : source_color = vec4(0.72, 0.33, 0.1, 1.0);
uniform vec4 pit_color : source_color = vec4(0.36, 0.14, 0.05, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.75;
// how bright the steel left showing is against the blade's own colour (1 = as it is; the Saw Halo keeps its gold)
uniform float steel : hint_range(0.0, 1.5) = 1.0;
// how dark the pits and the rim get (0 = none, 1 = all the way to pit_color)
uniform float pits : hint_range(0.0, 1.0) = 0.7;
// patches across a metre of blade
uniform float scale = 2.2;
// the dark rim, as a share of the radius from the edge in (0 = none), and the blade's radius in its own metres
uniform float rim = 0.22;
uniform float radius = 0.38;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_local;
// how rusty a spot must be before it pits (pass 64: 0.78 before, which pitted every thick patch dark red)
const float PIT_FROM = 0.9;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local.xz;
	float n = texture(noise_tex, p * scale + vec2(0.37, 0.11)).r * 0.65 + texture(noise_tex, p * scale * 2.7 + vec2(0.71, 0.53)).r * 0.35;
	// how rusty this spot is: `amount` on average, the noise pushing it either way
	float r = clamp(amount + (n - 0.5) * 1.5, 0.0, 1.0);
	vec3 metal = base_color.rgb * steel;
	vec3 col = mix(metal, rust_color.rgb, smoothstep(0.3, 0.62, r));
	// pits in the thickest rust
	col = mix(col, pit_color.rgb, smoothstep(PIT_FROM, 1.0, r) * pits);
	// the oxidised rim (the sides of the disc sit on it too)
	float d = length(p) / max(radius, 0.01);
	col = mix(col, pit_color.rgb, smoothstep(1.0 - rim, 1.0, d) * amount * pits * 0.8);
	// scraped-clean glints of the old metal
	col = mix(col, metal * 1.15, smoothstep(0.18, 0.0, r) * 0.5);
	ALBEDO = col;
}
