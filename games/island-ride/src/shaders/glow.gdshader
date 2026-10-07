// Leuchtpunkt (G6): Lichthof um Laternen und Leuchtfeuer bei Nacht – Billboard-Quad, additiv, ungeleuchtet, radial
// ausgeblendet. Farbe je Instanz (MultiMesh-Farbe), Helligkeit über `intensity`. Läuft auch im Compatibility-Renderer.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;

void vertex() {
	// Zur Kamera drehen, Lage (und Größe des Quads) bleiben.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.22, r);
	float halo = pow(1.0 - clamp(r, 0.0, 1.0), 2.5);
	ALBEDO = COLOR.rgb * intensity * (core * 2.0 + halo * 0.8);
}
