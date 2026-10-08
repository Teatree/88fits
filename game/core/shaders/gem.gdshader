// The XP gems and the vacuum gem (pass 60, Garry: the gems "a shade darker so they are more easily visible on the sand",
// "maybe add low emit to them", and "a cheap shader that makes the gems look like they are 'charged' while they are
// flying" on the big magnet pulls): one material a kind on PickupManager's gem MultiMeshes (PickupManager.gem_material).
// Lit, so the octahedron's flat facets read against each other; `albedo` is the kind's colour (PickupManager.COLOURS) and
// `rest_emission` its low glow lying on the sand. INSTANCE_CUSTOM.x = the charge 0..1 (PickupManager.charge_of: 1 on the
// magnet arc, 0 on the sand and on the walk-up hop), INSTANCE_CUSTOM.y = the gem's seed. Charged, the glow is the
// stone's own colour at full brightness (its pass-46 colour, pushed toward its pure hue) at `charged_emission` with a
// shimmer at about `shimmer_hz` offset by the seed, the lit stone fades back under it so the sum keeps its hue (the
// Compatibility renderer has no tonemapping: past 1 every channel clips, and at 1.8 the gems had read as white paper
// scraps), and a thin pale rim comes up where a facet turns edge-on to the camera (a fresnel). No textures and no second
// pass: a charged gem costs the same draw as a plain one.
// Pass 54's rules kept: see-through (ALPHA 1) and writing no depth at PickupManager.PICKUP_PRIORITY (set on the
// material), drawn only where no painting wrote stencil 1 (PAINTING_STENCIL: enemy_billboard, sprite_billboard,
// prop_billboard), so a gem at a creature's or the hero's feet lies under the painting.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec3 albedo : source_color = vec3(0.4836, 0.3744, 0.78);
// the glow lying on the sand, and at full charge (before the shimmer)
uniform float rest_emission = 0.3;
uniform float charged_emission = 1.15;
uniform float shimmer_hz = 7.0;
// how thin the charged rim is (a higher power = a thinner rim) and how bright
uniform float rim_power = 3.0;
uniform float rim_strength = 0.6;

varying float v_charge;
varying float v_seed;

void vertex() {
	v_charge = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.y;
}

void fragment() {
	float ch = v_charge;
	// the charge's colour: the stone's own hue and saturation at full brightness (its pass-46 colour: GEM_SHADE divided
	// out, so no second uniform), lifted a little towards white
	float top = max(albedo.r, max(albedo.g, albedo.b));
	vec3 bright = albedo / max(top, 0.001);
	// ... and pushed toward its pure hue (the lowest channel taken out), so a charged gem reads as a saturated glowing
	// stone in its own colour, not as pale paper (the first capture had mixed it 30 % toward white)
	float low = min(bright.r, min(bright.g, bright.b));
	vec3 pure = (bright - vec3(low)) / max(1.0 - low, 0.001);
	vec3 glow = mix(bright, pure, 0.55 * ch);
	// the shimmer: shimmer_hz a second, each gem on its own beat, a fifth either way
	float shimmer = 0.5 + 0.5 * sin((TIME * shimmer_hz + v_seed) * 6.2831853);
	float energy = mix(rest_emission, charged_emission * (0.8 + 0.4 * shimmer), ch);
	// the rim: a facet turned edge-on to the camera pales, only while charged
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec3 pale = mix(bright, vec3(1.0), 0.7);
	// charged, the glow does the showing: the lit stone fades back, so the sum does not wash out to white
	ALBEDO = albedo * (1.0 - 0.7 * ch);
	EMISSION = mix(albedo, glow, ch) * energy + pale * rim * ch * rim_strength;
	ROUGHNESS = 0.7;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
