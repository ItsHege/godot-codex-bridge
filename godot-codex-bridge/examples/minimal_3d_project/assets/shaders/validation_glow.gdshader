shader_type spatial;

uniform float glow_strength = 0.25;
uniform vec4 tint_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform sampler2D detail_texture : source_color, repeat_enable;

void fragment() {
	vec3 detail = texture(detail_texture, UV).rgb;
	ALBEDO = mix(tint_color.rgb, detail, 0.35);
	EMISSION = tint_color.rgb * glow_strength;
}
