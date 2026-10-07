// Meer (G3): Wellen als Normalen-Störung (Summe gerichteter Sinuswellen, zur Ferne ausgeblendet – kein Flimmern),
// Glitzern über geringe Rauheit, türkisfarbenes Flachwasser und Brandung an der Küste. Die Wassertiefe kommt aus
// einer kleinen Höhenkarte des Geländes (`shore`, L8, 0 = SHORE_MIN_M … 1 = SHORE_MAX_M), nicht aus dem
// Tiefenpuffer – so läuft es auch im Compatibility-Renderer (Web).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D shore : filter_linear, repeat_disable;
// Weltlage (x, z) und Größe des Bereichs der Höhenkarte.
uniform vec2 shore_origin;
uniform vec2 shore_size = vec2(1.0);
uniform float shore_min_m = -20.0;
uniform float shore_max_m = 5.0;
uniform vec4 deep_color : source_color = vec4(0.03, 0.22, 0.42, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.62, 0.66, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 0.98, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Wassertiefe (m, positiv) an (x, z); außerhalb der Karte tief.
float depth_at(vec2 xz) {
	vec2 uv = (xz - shore_origin) / shore_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 40.0;
	}
	return -mix(shore_min_m, shore_max_m, texture(shore, uv).r);
}

// Steigung einer gerichteten Welle (Richtung d, Wellenzahl k, Amplitude a, Kreisfrequenz w).
vec2 wave(vec2 p, vec2 d, float k, float a, float w) {
	return d * (k * a * cos(dot(p, d) * k + TIME * w));
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(60.0, 600.0, dist);
	float far = 1.0 - smoothstep(400.0, 2500.0, dist);
	vec2 slope = far * (wave(p, normalize(vec2(1.0, 0.35)), 0.09, 0.35, 1.1)
			+ wave(p, normalize(vec2(-0.4, 1.0)), 0.13, 0.22, 1.4)
			+ wave(p, normalize(vec2(0.8, -0.6)), 0.21, 0.12, 1.9));
	slope += near * (wave(p, normalize(vec2(0.2, 1.0)), 0.7, 0.03, 3.1)
			+ wave(p, normalize(vec2(1.0, -0.3)), 1.1, 0.018, 3.9));
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float depth = depth_at(p);
	float shallow = 1.0 - smoothstep(0.3, 12.0, depth);
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, shallow);
	// Brandung: Schaumstreifen laufen zur Küste, dazu ein heller Saum an der Wasserlinie.
	float band = 1.0 - smoothstep(0.0, 2.6, depth);
	float stripes = 0.5 + 0.5 * sin(depth * 4.5 + TIME * 1.7 + sin(p.x * 0.07) * 1.5 + sin(p.y * 0.05) * 1.5);
	float foam = band * smoothstep(0.6, 0.95, stripes) * 0.8 + (1.0 - smoothstep(0.0, 0.5, depth)) * 0.7;
	foam = clamp(foam, 0.0, 1.0);
	ALBEDO = mix(color, foam_color.rgb, foam);
	ROUGHNESS = mix(0.06, 0.7, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(mix(0.94, 0.55, shallow) + foam, 0.0, 1.0);
}
