shader_type canvas_item;
// Per-character shader: white hit-flash plus an optional tint (champions).

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.95, 0.9, 1.0);
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb *= tint.rgb;
	c.rgb = mix(c.rgb, flash_color.rgb * 1.6, flash * 0.85);
	COLOR = c;
}
