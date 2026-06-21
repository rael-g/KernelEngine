#version 450

layout(set = 0, binding = 0) uniform Uniforms {
    float angle;
} u;

vec2 positions[3] = vec2[](
    vec2( 0.0, -0.5),
    vec2( 0.5,  0.5),
    vec2(-0.5,  0.5)
);

vec3 colors[3] = vec3[](
    vec3(1.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 1.0)
);

layout(location = 0) out vec3 v_color;

void main() {
    float c = cos(u.angle);
    float s = sin(u.angle);
    vec2 p = positions[gl_VertexIndex];
    gl_Position = vec4(c * p.x - s * p.y, -(s * p.x + c * p.y), 0.0, 1.0);
    v_color = colors[gl_VertexIndex];
}
