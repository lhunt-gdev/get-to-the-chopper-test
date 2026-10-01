shader_type canvas_item;
// The rear-view CCTV monitor (Alert 3 squad): the rear camera's picture as grainy green
// security footage. Flipped left to right like a mirror, so a guard in your left lane shows
// on the left.

void fragment() {
	vec2 uv = vec2(1.0 - UV.x, UV.y);
	// The odd line tears sideways a little.
	float line = floor(uv.y * 72.0);
	float tear = fract(sin(line * 12.9898 + floor(TIME * 10.0) * 7.31) * 43758.5453);
	uv.x += step(0.94, tear) * (tear - 0.97) * 0.08;
	vec3 c = texture(TEXTURE, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	l = pow(clamp(l * 1.7, 0.0, 1.0), 0.75);
	vec3 g = vec3(0.5, 0.95, 0.58) * l + vec3(0.02, 0.05, 0.03);
	g *= 0.8 + 0.2 * step(0.5, fract(UV.y * 36.0));  // scanlines
	float n = fract(sin(dot(UV * 97.0 + fract(TIME) * 13.0, vec2(12.9898, 78.233))) * 43758.5453);
	g += (n - 0.5) * 0.09;  // grain
	vec2 v = UV - 0.5;
	g *= 1.0 - dot(v, v) * 1.4;  // vignette
	COLOR = vec4(g, 1.0);
}
