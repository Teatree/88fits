// A hero still to unlock: the painting's shape filled flat with one colour (the details stay a secret).
shader_type canvas_item;

uniform vec4 fill : source_color = vec4(0.141, 0.106, 0.078, 0.94);

void fragment() {
	// COLOR arrives as the texture sample times the vertex colour: keep its coverage, drop its colours
	COLOR = vec4(fill.rgb, COLOR.a * fill.a);
}
