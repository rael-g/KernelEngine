using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_bind_group_layout_entry
{
    [NativeTypeName("uint32_t")]
    public uint binding;

    [NativeTypeName("ke_gpu_shader_stage")]
    public uint visibility;

    public ke_gpu_binding_type type;

    [NativeTypeName("ke_bool")]
    public byte has_dynamic_offset;
}
