// The Big Mouth's throat glow (pass 87; Garry: "keep a kind of a bright shining thing in the back of the Mouth when
// it's shooting the Laser"): one camera-facing quad in the mouth's opening, a white-hot heart in the beam's colour with a
// soft halo and a few slow rays. Depth-tested, so the lips and teeth stand in front of it and it only shows through the
// open mouth; alpha-blended like the beam, so the colour holds over bright sand. LaserBeam.gd sets its size by the
// quad's scale and `strength` by how bright the throat burns (0 at rest, rising through the wind-up, 1 while it pours)
// and how far the mouth faces the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.7, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength = 1.0;
// drawn this far towards the camera (metres), so the quad clears the throat's walls behind it
uniform float push = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	vec3 world = origin + cam_back * push + right * VERTEX.x * s + up * VERTEX.y * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float heart = exp(-r * r * 22.0);
	float halo = exp(-r * r * 4.5) * (1.0 - smoothstep(0.75, 1.0, r));
	float ang = atan(p.y, p.x);
	float rays = pow(0.5 + 0.5 * cos(ang * 5.0 + TIME * 1.7), 8.0) * exp(-r * r * 3.0) * 0.45;
	ALBEDO = mix(color.rgb * 1.15, core_color.rgb, clamp(heart * 1.6, 0.0, 1.0));
	ALPHA = clamp((halo * 0.8 + rays + heart) * strength, 0.0, 1.0);
}
