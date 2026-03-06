$input v_normal, v_viewPos

#include <bgfx_shader.sh>

void main()
{
    // MRT[0]: view-space normal packed to [0, 1]
    gl_FragData[0] = vec4(normalize(v_normal) * 0.5 + 0.5, 1.0);
    // MRT[1]: positive linear depth (|view_z|)
    gl_FragData[1] = vec4(-v_viewPos.z, 0.0, 0.0, 1.0);
}
