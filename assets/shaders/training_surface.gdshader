shader_type spatial;
render_mode unshaded;

uniform vec4 surface_color : source_color = vec4(0.035, 0.057, 0.079, 1.0);
uniform vec4 seam_color : source_color = vec4(0.07, 0.12, 0.15, 1.0);
uniform vec2 panel_count = vec2(12.0, 8.0);
uniform float seam_strength = 0.5;

void fragment() {
	vec2 panels = UV * panel_count;
	vec2 cell_edge = abs(fract(panels - 0.5) - 0.5);
	vec2 edge_width = max(fwidth(panels), vec2(0.002));
	vec2 seams = 1.0 - smoothstep(vec2(0.0), edge_width * 1.4, cell_edge);
	float seam = max(seams.x, seams.y) * seam_strength;
	float center_light = 1.0 - smoothstep(0.15, 0.75, length(UV - vec2(0.5)));
	ALBEDO = mix(surface_color.rgb * (0.78 + 0.22 * center_light), seam_color.rgb, seam);
}
