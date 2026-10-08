// Geschwindigkeitslinien (#42): feine helle Striche, die vom Bildrand nach außen ziehen; die Bildmitte bleibt frei.
// Stärke 0..1 über `strength` (SpeedEffects). Läuft auch im Compatibility-Renderer.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float turn = atan(p.y, p.x) / TAU + 0.5;
	float bins = 150.0;
	float id = floor(turn * bins);
	float across = abs(fract(turn * bins) - 0.5);
	float width = 0.06 + 0.08 * hash(id + 7.0);
	float line = 1.0 - smoothstep(0.0, width, across);
	// Strich zieht nach außen; jede Spur mit eigenem Tempo, eigener Phase und eigener Länge
	float along = fract(r * (0.9 + 0.8 * hash(id + 3.0)) - TIME * (0.9 + 1.4 * hash(id + 5.0)) + hash(id));
	float streak = smoothstep(0.0, 0.08, along) * (1.0 - smoothstep(0.25, 0.5 + 0.3 * hash(id + 9.0), along));
	// Nur ein Teil der Spuren ist belegt
	float used = step(hash(id + 11.0), 0.6);
	float mask = smoothstep(0.38, 0.85, r);
	COLOR = vec4(1.0, 1.0, 1.0, 0.42 * strength * line * streak * used * mask);
}
