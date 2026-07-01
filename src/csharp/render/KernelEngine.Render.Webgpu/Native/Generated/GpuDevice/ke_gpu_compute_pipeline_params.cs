using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_compute_pipeline_params
{
    [NativeTypeName("ke_gpu_shader_module")]
    public ulong compute_module;

    [NativeTypeName("const char *")]
    public sbyte* compute_entry;

    [NativeTypeName("ke_gpu_bind_group_layout[4]")]
    public _bind_group_layouts_e__FixedBuffer bind_group_layouts;

    [NativeTypeName("uint32_t")]
    public uint bind_group_layout_count;

    [InlineArray(4)]
    public partial struct _bind_group_layouts_e__FixedBuffer
    {
        public ulong e0;
    }
}
