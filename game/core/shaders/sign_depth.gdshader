// The signposts' depth (pass 60, Garry: "Hero should render above the road sign, unless the hero is north of it, in that
// case it should render below"). A sign is the one upright 3D thing among the paintings: the hero, the creatures and the
// props are camera-facing quads whose every pixel carries the depth of their feet, so any two of them sort by their feet,
// the southern one over the northern. An upright post's top is nearer the camera than its foot, so a hero standing just
// south of a post (nearer than its foot, farther than its top) was cut through by it, and its arms reached over him from
// a metre and a half away. This material keeps every vertex where it is on the screen and gives it the depth of the
// sign's FOOT instead, compressed by `squash` about that foot (the arms and the post still sort among themselves) and
// pushed `bias` metres back (ties go to the paintings). A sign then sorts like a painting standing at its foot: a hero
// south of it draws over it, north of it under it (and his outline pass draws him through it, as through any prop).
// One material per sign: `foot` is its world position (SignField paints every post and arm with its own). The sign
// casts no shadow (SignField) and takes none (shadows_disabled): a shadow looked up at the moved depth would be wrong.
// Pass 72 (lane SPEC): a sign is scenery and writes stencil 2 (SceneryStencil.VALUE): a creature it hides is outlined.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, shadows_disabled;
stencil_mode write, compare_always, 2;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// the sign's foot in the world
uniform vec3 foot = vec3(0.0);
// how much of the sign's own depth is kept about the foot, and how far back the whole sign goes (metres)
uniform float squash = 0.02;
uniform float bias = 0.03;

void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float z_foot = (VIEW_MATRIX * vec4(foot, 1.0)).z;
	// view space looks down -Z: whatever is drawn has a negative z, and farther is more negative
	float z0 = min(view.z, -0.01);
	float zf = min(z_foot, -0.01);
	float z1 = min(zf + (z0 - zf) * squash - bias, -0.005);
	// the very same pixel: x and y scale with z under the perspective divide
	VERTEX = vec3(view.xy * (z1 / z0), z1);
	NORMAL = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
