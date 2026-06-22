using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_capabilities
{
    [NativeTypeName("uint32_t")]
    public uint max_texture_dimension_2d;

    [NativeTypeName("uint32_t")]
    public uint max_texture_array_layers;

    [NativeTypeName("uint32_t")]
    public uint max_bind_groups;

    [NativeTypeName("uint32_t")]
    public uint max_vertex_attributes;

    [NativeTypeName("uint32_t")]
    public uint max_vertex_buffers;

    [NativeTypeName("uint32_t")]
    public uint max_uniform_buffer_size;

    [NativeTypeName("uint32_t")]
    public uint max_storage_buffer_size;

    [NativeTypeName("uint32_t")]
    public uint max_compute_workgroup_size_x;

    [NativeTypeName("uint32_t")]
    public uint max_compute_workgroup_size_y;

    [NativeTypeName("uint32_t")]
    public uint max_compute_workgroup_size_z;

    [NativeTypeName("ke_bool")]
    public byte supports_bindless;

    [NativeTypeName("ke_bool")]
    public byte supports_mesh_shaders;

    [NativeTypeName("ke_bool")]
    public byte supports_ray_tracing;
}
