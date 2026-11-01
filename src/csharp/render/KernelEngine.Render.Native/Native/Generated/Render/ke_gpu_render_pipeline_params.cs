using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_render_pipeline_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;

    [NativeTypeName("ke_gpu_shader_module")]
    public ulong vertex_module;

    [NativeTypeName("ke_gpu_shader_module")]
    public ulong fragment_module;

    [NativeTypeName("const char *")]
    public sbyte* vertex_entry;

    [NativeTypeName("const char *")]
    public sbyte* fragment_entry;

    [NativeTypeName("ke_gpu_primitive_topology")]
    public global::KernelEngine.Render.GpuPrimitiveTopology primitive_topology;

    [NativeTypeName("ke_gpu_cull_mode")]
    public global::KernelEngine.Render.GpuCullMode cull_mode;

    [NativeTypeName("ke_gpu_front_face")]
    public global::KernelEngine.Render.GpuFrontFace front_face;

    [NativeTypeName("uint32_t")]
    public uint vertex_buffer_count;

    [NativeTypeName("const ke_gpu_vertex_buffer_layout *")]
    public GpuVertexBufferLayout* vertex_buffers;

    [NativeTypeName("ke_gpu_blend_state")]
    public global::KernelEngine.Render.GpuBlendState blend_state;

    [NativeTypeName("ke_gpu_depth_stencil_state")]
    public global::KernelEngine.Render.GpuDepthStencilState depth_stencil;

    [NativeTypeName("ke_gpu_bind_group_layout[4]")]
    public _bind_group_layouts_e__FixedBuffer bind_group_layouts;

    [NativeTypeName("uint32_t")]
    public uint bind_group_layout_count;

    public bool alpha_to_coverage_enabled;

    [NativeTypeName("ke_gpu_texture_format[8]")]
    public _color_target_formats_e__FixedBuffer color_target_formats;

    [NativeTypeName("uint32_t")]
    public uint color_target_count;

    [InlineArray(4)]
    public partial struct _bind_group_layouts_e__FixedBuffer
    {
        public ulong e0;
    }

    [InlineArray(8)]
    public partial struct _color_target_formats_e__FixedBuffer
    {
        public global::KernelEngine.Render.GpuTextureFormat e0;
    }
}
