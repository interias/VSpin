// Vegetation im Wind (G3): sanftes Wiegen, unten fest – Gewicht = Höhe im Objektraum (0 am Fuß, 1 an der Spitze).
// Ersetzt das StandardMaterial3D der Kenney-Vegetation (Farbe, Rauheit übernommen) und das Vertex-Farben-Material
// der Agaven. Phase je Instanz aus der Weltlage (MultiMesh ohne Custom Data); läuft auch im Compatibility-Renderer.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
// Vertex-Farben (sRGB) mit der Albedo multiplizieren; linearisiert wie bei `vertex_color_is_srgb` nur, wenn das
// Rendering linear rechnet (im Compatibility-Renderer/Web nicht).
uniform bool use_vertex_color = false;
uniform float roughness = 1.0;
// Modellhöhe im Objektraum.
uniform float height = 1.0;
// Ausschlag an der Spitze als Anteil der Höhe.
uniform float strength = 0.02;

void vertex() {
	float w = clamp(VERTEX.y / height, 0.0, 1.0);
	w *= w;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.031 + origin.z * 0.027;
	float gust = 0.65 + 0.35 * sin(TIME * 0.3 + origin.x * 0.004 + origin.z * 0.003);
	float sway = (sin(TIME * 1.4 + phase) + 0.35 * sin(TIME * 3.3 + phase * 1.7)) * gust;
	float reach = strength * height * w;
	VERTEX.x += sway * reach;
	VERTEX.z += 0.5 * cos(TIME * 1.1 + phase) * gust * reach;
}

void fragment() {
	vec3 color = albedo.rgb;
	if (use_vertex_color) {
		vec3 c = COLOR.rgb;
		if (!OUTPUT_IS_SRGB) {
			c = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
		}
		color *= c;
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
}
