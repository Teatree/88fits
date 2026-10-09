// The gold coin on the sand (pass 52, Garry: "it's not visible right now, it blends in with the floor sand way too
// well"): a coin read like the UI's painted one, unshaded so the sun never washes it into the ground. Its faces are a
// bright raised centre, a darker sunk ring, a pale lip and a dark brown outline; its edge is that dark brown, so a coin
// spinning edge-on is a dark stroke, never a gold one on gold sand; and a glint sweeps across the faces now and then.
// Drawn on PickupManager's coin MultiMesh: a CylinderMesh lying along its local Y (the faces' normals are +-Y).
// Pass 54 (Garry: pickups drawn under every sprite): see-through (ALPHA 1) and writing no depth, at PickupManager's
// PICKUP_PRIORITY, and drawn only where no painting wrote stencil 1 (enemy_billboard, sprite_billboard, prop_billboard),
// so a coin at a creature's or the hero's feet lies under the painting; PickupManager sets `radius` to its mesh's.
// Pass 61 (Garry: the pickups must never disappear, at no cost): the coin is stood on its edge, spun and floated here, so
// a coin lying on the sand never has its instance written again. INSTANCE_CUSTOM.y is the coin's seed, 0..1, its phase
// seed x TAU (PickupManager.phase_of, as the gems'); the spin is 3 t + phase about the upright, inside the instance's
// basis (an arc's extra spin and pop, a tossed coin's tumble), and the float lifts it float_base + bob sin(2.4 t + 0.9
// phase) metres straight up in the world whatever that basis is (the review of pass 61: read off the basis, the phase had
// jumped as an arc spun it); `t_now` is the run's clock (PickupManager._render, wrapped at PickupManager.COIN_WRAP), so it
// stops when the run pauses. The face pattern still reads the mesh's own corners.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never, blend_mix;
stencil_mode read, compare_not_equal, 1;

uniform vec3 face_hi : source_color = vec3(1.0, 0.88, 0.34);
uniform vec3 face_lo : source_color = vec3(0.9, 0.56, 0.1);
uniform vec3 lip : source_color = vec3(1.0, 0.95, 0.62);
uniform vec3 rim : source_color = vec3(0.34, 0.16, 0.03);
uniform float radius = 0.28;
// seconds between two glints, and how bright one is
uniform float glint_every = 1.6;
uniform float glint = 0.55;
// the float and the spin (pass 61): the run's clock, the float's height either way and its middle over the rest
uniform float t_now = 0.0;
uniform float bob = 0.09;
uniform float float_base = 0.06;

varying vec3 v_n;
varying vec3 v_p;

void vertex() {
	v_n = NORMAL;
	v_p = VERTEX;
	// on its edge (the cylinder's axis laid flat), then spun about the upright
	vec3 e = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	float phase = INSTANCE_CUSTOM.y * 6.2831853;
	float a = t_now * 3.0 + phase;
	float c = cos(a);
	float s = sin(a);
	VERTEX = vec3(e.x * c + e.z * s, e.y, e.z * c - e.x * s);
	// the float, straight up in the world: the basis is a turn times an even scale, so its inverse is its transpose over
	// the scale squared
	mat3 m = mat3(MODEL_MATRIX);
	float lift = float_base + sin(t_now * 2.4 + phase * 0.9) * bob;
	VERTEX += transpose(m) * vec3(0.0, lift, 0.0) / max(dot(m[0], m[0]), 0.000001);
}

void fragment() {
	vec3 col;
	if (abs(v_n.y) < 0.5) {
		// the edge
		col = rim;
	} else {
		float r = length(v_p.xz) / radius;
		col = mix(face_hi, face_lo, smoothstep(0.5, 0.62, r));
		col = mix(col, lip, smoothstep(0.66, 0.72, r) * (1.0 - smoothstep(0.76, 0.8, r)));
		col = mix(col, rim, smoothstep(0.82, 0.88, r));
		// a glint: a pale band across the face, quick, every glint_every seconds (each coin at its own moment)
		float phase = fract(TIME / glint_every + dot(MODEL_MATRIX[3].xyz, vec3(0.37, 0.0, 0.53)));
		float band = (v_p.x + v_p.z) / (radius * 2.0) - (phase * 8.0 - 1.0);
		col = mix(col, vec3(1.0, 0.98, 0.86), glint * (1.0 - smoothstep(0.0, 0.12, abs(band))) * step(r, 0.84));
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
