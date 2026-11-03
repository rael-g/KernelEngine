using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_mesh_shape_data
{
    [NativeTypeName("ke_vertex *")]
    public global::KernelEngine.Render.Vertex* vertices;

    [NativeTypeName("uint32_t")]
    public uint vertex_count;

    [NativeTypeName("uint16_t *")]
    public ushort* indices;

    [NativeTypeName("uint32_t")]
    public uint index_count;
}
