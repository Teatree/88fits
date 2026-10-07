// The Strongbox's flying coins (pass 58, Garry: "coins flying out of the player and into the chest ... they should be 3D
// coins ... Keep in mind that coins are yellow and the background is oftentimes yellow so they need to be noticeable"):
// the pickup coin's look (core/shaders/coin.gdshader: a bright raised face, a darker sunk ring, a pale lip, a dark brown
// outline and edge, unshaded so the sun never washes it into the sand) on CoinStream's MultiMesh, with a thicker dark
// outline, since a coin in the air has only sand behind it, and its glint driven per coin: it sweeps across the face as
// the coin flies, brighter the more gold the stream carries, and the coin flashes pale as it drops into the box.
// Opaque and depth-tested (not the pickups' see-through pass under every painting): a coin in the air is in front of
// whatever stands behind it and behind whatever stands in front of it.
// A CylinderMesh lying along its local Y (the faces' normals are +-Y), `radius` its radius.
// INSTANCE_CUSTOM: x = where the glint is (0..1 across the face), y = how bright it is, z = the pale flash (0..1)
// INSTANCE COLOR:  unused (on: a MultiMesh with custom data needs its colours on, or the custom data reads 0)
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 face_hi : source_color = vec3(1.0, 0.88, 0.34);
uniform vec3 face_lo : source_color = vec3(0.9, 0.56, 0.1);
uniform vec3 lip : source_color = vec3(1.0, 0.95, 0.62);
uniform vec3 rim : source_color = vec3(0.3, 0.13, 0.02);
uniform float radius = 0.3;
// where the dark outline starts on the face (the pickup coin's is 0.82)
uniform float outline = 0.76;

varying vec3 v_n;
varying vec3 v_p;
varying vec3 v_custom;

void vertex() {
	v_n = NORMAL;
	v_p = VERTEX;
	v_custom = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	vec3 col;
	if (abs(v_n.y) < 0.5) {
		// the edge: dark, so a coin turning edge-on is a dark stroke on the sand, never a gold one
		col = rim;
	} else {
		float r = length(v_p.xz) / radius;
		col = mix(face_hi, face_lo, smoothstep(0.46, 0.56, r));
		col = mix(col, lip, smoothstep(0.6, 0.65, r) * (1.0 - smoothstep(0.69, 0.73, r)));
		col = mix(col, rim, smoothstep(outline, outline + 0.06, r));
		// the glint: a pale band across the face where the coin says it is
		float band = (v_p.x + v_p.z) / (radius * 2.0) - (v_custom.x * 3.0 - 1.5);
		col = mix(col, vec3(1.0, 0.98, 0.86), v_custom.y * (1.0 - smoothstep(0.0, 0.14, abs(band))) * step(r, outline));
	}
	// dropping into the box: a pale flash over all of it
	col = mix(col, vec3(1.0, 0.97, 0.8), clamp(v_custom.z, 0.0, 1.0) * 0.7);
	ALBEDO = col;
}
