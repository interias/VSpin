// Lichtkegel des Leuchtturms (G3): additiv, ungeleuchtet, zur Spitze und zu den Rändern hin ausgeblendet.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.88, 0.6, 1.0);
uniform float intensity = 0.18;

varying float along;

void vertex() {
	// Zylinder entlang lokal y: oben (y = +h/2) an der Lampe, unten weit draußen.
	along = UV.y;
}

void fragment() {
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade = (1.0 - along) * (1.0 - along);
	ALBEDO = color.rgb * intensity * fade * edge * edge;
}
