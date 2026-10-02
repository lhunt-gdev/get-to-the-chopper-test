shader_type canvas_item;
// The rear-view CCTV monitor (Alert 3 squad): the rear camera's picture as grainy green
// security footage. Flipped left to right like a mirror, so a guard in your left lane shows
// on the left. It switches on like an old CRT (power 0 -> 1): a bright dot stretches into a
// thin line across the screen, the line opens up and down into the picture, and the picture
// starts over-bright and settles.

uniform float power : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// The switch-on: the line grows across (first quarter), then opens up and down.
	float across = smoothstep(0.0, 0.25, power);
	float open = smoothstep(0.22, 0.6, power);
	float height = mix(0.03, 1.0, open);
	vec2 c = UV - 0.5;
	bool lit = abs(c.x) <= across * 0.5 && abs(c.y) <= height * 0.5;
	if (!lit) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// The picture is squashed into the opening band, the way a CRT's picture opens up.
		vec2 uv = vec2(1.0 - UV.x, 0.5 + c.y / height);
		// The odd line tears sideways a little.
		float line = floor(uv.y * 72.0);
		float tear = fract(sin(line * 12.9898 + floor(TIME * 10.0) * 7.31) * 43758.5453);
		uv.x += step(0.94, tear) * (tear - 0.97) * 0.08;
		vec3 col = texture(TEXTURE, uv).rgb;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		l = pow(clamp(l * 1.7, 0.0, 1.0), 0.75);
		vec3 g = vec3(0.5, 0.95, 0.58) * l + vec3(0.02, 0.05, 0.03);
		g *= 0.8 + 0.2 * step(0.5, fract(UV.y * 36.0));  // scanlines
		float n = fract(sin(dot(UV * 97.0 + fract(TIME) * 13.0, vec2(12.9898, 78.233))) * 43758.5453);
		g += (n - 0.5) * 0.09;  // grain
		g *= 1.0 - dot(c, c) * 1.4;  // vignette
		// Over-bright as it warms up, settling by the end; the thin line itself is near white.
		float warm = 1.0 + 1.6 * (1.0 - smoothstep(0.45, 1.0, power));
		g = mix(vec3(0.85, 1.0, 0.9), g * warm, open);
		COLOR = vec4(g, 1.0);
	}
}
