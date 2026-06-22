using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_render_pipeline_params
{
    [NativeTypeName("ke_gpu_shader_module")]
    public ulong vertex_module;

    [NativeTypeName("ke_gpu_shader_module")]
    public ulong fragment_module;

    [NativeTypeName("const char *")]
    public sbyte* vertex_entry;

    [NativeTypeName("const char *")]
    public sbyte* fragment_entry;

    public ke_gpu_primitive_topology primitive_topology;

    public ke_gpu_cull_mode cull_mode;

    public ke_gpu_front_face front_face;

    [NativeTypeName("uint32_t")]
    public uint vertex_buffer_count;

    [NativeTypeName("const ke_gpu_vertex_buffer_layout *")]
    public ke_gpu_vertex_buffer_layout* vertex_buffers;

    public ke_gpu_blend_state blend_state;

    public ke_gpu_depth_stencil_state depth_stencil;

    [NativeTypeName("ke_gpu_bind_group_layout[4]")]
    public _bind_group_layouts_e__FixedBuffer bind_group_layouts;

    [NativeTypeName("uint32_t")]
    public uint bind_group_layout_count;

    [NativeTypeName("ke_bool")]
    public byte alpha_to_coverage_enabled;

    public ke_gpu_texture_format color_target_format;

    [InlineArray(4)]
    public partial struct _bind_group_layouts_e__FixedBuffer
    {
        public ulong e0;
    }
}
