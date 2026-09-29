shader_type canvas_item;
// Темнота ночной главы: светлое пятно вокруг феи
uniform vec2 light_pos = vec2(0.0);
uniform float light_radius = 130.0;
uniform vec4 dark_color : source_color = vec4(0.055, 0.047, 0.133, 0.9);

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	float d = distance(world_pos, light_pos);
	float a = smoothstep(light_radius * 0.35, light_radius, d);
	COLOR = vec4(dark_color.rgb, dark_color.a * a);
}
