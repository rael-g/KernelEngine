using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct GpuVertexBufferLayout
{
    [NativeTypeName("uint64_t")]
    public ulong Stride;

    [NativeTypeName("ke_gpu_vertex_step_mode")]
    public global::KernelEngine.Render.GpuVertexStepMode StepMode;

    [NativeTypeName("uint32_t")]
    public uint AttributeCount;

    [NativeTypeName("const ke_gpu_vertex_attribute *")]
    public global::KernelEngine.Render.GpuVertexAttribute* Attributes;
}
