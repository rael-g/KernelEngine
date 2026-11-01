using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_bind_group_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;

    [NativeTypeName("ke_gpu_bind_group_layout")]
    public ulong layout;

    [NativeTypeName("uint32_t")]
    public uint entry_count;

    [NativeTypeName("const ke_gpu_bind_group_entry *")]
    public global::KernelEngine.Render.GpuBindGroupEntry* entries;
}
