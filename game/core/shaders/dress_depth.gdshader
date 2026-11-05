// The map's 3D dressing (pass 126, lane DRESS: the telephone poles, the cart's wheels, the grave crosses; MapDressing merges
// them into one mesh, one draw). Like the signs (sign_depth.gdshader, pass 60) every vertex stays where it is on the screen
// and takes the depth of its own thing's FOOT, so a pole or a cross sorts against the hero, the creatures and the props the
// way two paintings do (south over north), and a hero just south of a 5.6 m pole is never cut through by its top. The sign has
// one foot a material; here the mesh is merged, so each vertex carries its foot: UV = (foot x, foot z), UV2.x = foot y.
// COLOR.rgb is the paint (linear). COLOR.a picks how much of a vertex's own depth about the foot is kept: 1 = an upright thing
// (the signs' numbers: `squash` of its height, `squash_h` of its run over the ground); 0 = a thing lying low on the sand (a
// wheel, the snapped-off top): its whole run over the ground and `low_squash` of its height, because a thing that lies flat
// squashed towards its foot would slide under the sand it lies on. What runs under the ground (a sunk wheel, a post's foot)
// is hidden by the terrain as it would be anyway. Scenery: writes stencil 4 (SceneryStencil.VALUE), no shadows of its own.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, shadows_disabled;
stencil_mode write, compare_always, 4;

uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform float squash = 0.02;
uniform float squash_h = 0.25;
uniform float low_squash = 0.25;
uniform float low_squash_h = 1.0;
// how far back the whole thing goes (metres; ties go to the paintings)
uniform float bias = 0.03;

void vertex() {
	vec3 foot = vec3(UV.x, UV2.x, UV.y);
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float z_foot = (VIEW_MATRIX * vec4(foot, 1.0)).z;
	// view space looks down -Z: whatever is drawn has a negative z, and farther is more negative
	float z0 = min(view.z, -0.01);
	float zf = min(z_foot, -0.01);
	vec3 off = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - foot;
	float z_run = (VIEW_MATRIX * vec4(off.x, 0.0, off.z, 0.0)).z;
	float z_up = (VIEW_MATRIX * vec4(0.0, off.y, 0.0, 0.0)).z;
	float keep_run = mix(low_squash_h, squash_h, COLOR.a);
	float keep_up = mix(low_squash, squash, COLOR.a);
	float z1 = min(zf + z_run * keep_run + z_up * keep_up - bias, -0.005);
	// the very same pixel: x and y scale with z under the perspective divide
	VERTEX = vec3(view.xy * (z1 / z0), z1);
	NORMAL = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
