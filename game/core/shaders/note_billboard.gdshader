// Musical notes for Fx (pass 46: the Guitarra's cone of melody): one camera-facing quad per note, cut from a small atlas
// of white glyphs with a dark outline (art/fx/notes.png, made by tools/gen_notes.py), tinted by the instance colour, so
// the outline stays dark whatever the tint. Before the atlas is imported (`has_atlas` off) a plain note is drawn instead:
// a round head with a stem.
// INSTANCE_CUSTOM: x = the glyph's cell in the atlas, y = its tilt in the screen's plane (radians)
// INSTANCE COLOR:  rgb = tint, a = opacity
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float cells = 4.0;
uniform bool has_atlas = true;
// drawn a little towards the camera, so a note flying through a creature reads in front of its sprite
uniform float toward_cam = 0.35;

varying vec4 v_col;
varying float v_cell;

void vertex() {
	v_col = COLOR;
	v_cell = INSTANCE_CUSTOM.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	float a = INSTANCE_CUSTOM.y;
	vec2 q = vec2(VERTEX.x * cos(a) - VERTEX.y * sin(a), VERTEX.x * sin(a) + VERTEX.y * cos(a));
	vec3 world = origin + cam_back * toward_cam + (right * q.x + up * q.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec4 t;
	if (has_atlas) {
		t = texture(atlas, vec2((UV.x + floor(v_cell + 0.5)) / cells, UV.y));
	} else {
		// no atlas yet: a note head low on the left and a stem up its right side, white
		vec2 p = UV * 2.0 - 1.0;
		float head = length(vec2((p.x + 0.18) / 0.5, (p.y - 0.5) / 0.36));
		float stem = step(abs(p.x - 0.26), 0.07) * step(-0.85, p.y) * step(p.y, 0.5);
		t = vec4(1.0, 1.0, 1.0, max(step(head, 1.0), stem));
	}
	ALBEDO = t.rgb * v_col.rgb;
	ALPHA = t.a * v_col.a;
}
