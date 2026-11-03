shader_type canvas_item;
// Full-screen overlay: dark vignette, a blood-red pulse when hurt, and film grain.

uniform float vignette = 0.55;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float grain = 0.045;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.4;
	float d = length(uv);
	float v = smoothstep(0.35, 0.95, d) * vignette;
	float h = smoothstep(0.25, 0.9, d) * hurt;
	float n = hash(floor(FRAGCOORD.xy / 2.0) + fract(TIME * 13.0) * 100.0) - 0.5;
	vec3 col = mix(vec3(0.0), vec3(0.45, 0.0, 0.02), h / max(v + h, 0.001));
	float a = clamp(v + h * 0.8, 0.0, 0.95);
	// grain: lighten / darken slightly
	COLOR = vec4(col + vec3(n * grain * 4.0), a + abs(n) * grain);
}
