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
// Pass 105 (lane LOOK): 4 now (SceneryStencil.VALUE; the table is in StageStencil's header).
stencil_mode write, compare_always, 4;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// the sign's foot in the world
uniform vec3 foot = vec3(0.0);
// how much of the sign's own depth is kept about the foot, and how far back the whole sign goes (metres)
uniform float squash = 0.02;
uniform float bias = 0.03;
// Pass 80 (lane WALLS; Garry: "There is some z-fighting on the sign 3d. Fix it"): `squash` squeezed ALL of the sign's
// own depth fifty times, so the board's stub behind the post and the part inside it lay a millimetre or less behind the
// post's face, under what a depth buffer can tell apart 25 m away: they flickered through the post as the camera moved.
// The depth a vertex owes to its HEIGHT over the foot is what made a tall post reach over a hero standing south of its
// foot; the depth it owes to its run over the GROUND is what sorts the sign's parts among themselves. So the height's
// share stays `squash` and the ground's is kept `squash_h` of what it is: a board's faces now lie six times further
// apart than before, and a board pointing at the camera still sorts under a hero standing beside the post (its tip
// 1.1 m out comes 0.2 m nearer than the foot, the hero's feet 0.4 m when he stands against the post's south side).
uniform float squash_h = 0.25;

void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float z_foot = (VIEW_MATRIX * vec4(foot, 1.0)).z;
	// view space looks down -Z: whatever is drawn has a negative z, and farther is more negative
	float z0 = min(view.z, -0.01);
	float zf = min(z_foot, -0.01);
	// the vertex's offset from the foot, split into its run over the ground and its height: their shares of the view
	// depth (the two add up to z0 - zf)
	vec3 off = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - foot;
	float z_run = (VIEW_MATRIX * vec4(off.x, 0.0, off.z, 0.0)).z;
	float z_up = (VIEW_MATRIX * vec4(0.0, off.y, 0.0, 0.0)).z;
	float z1 = min(zf + z_run * squash_h + z_up * squash - bias, -0.005);
	// the very same pixel: x and y scale with z under the perspective divide
	VERTEX = vec3(view.xy * (z1 / z0), z1);
	NORMAL = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
