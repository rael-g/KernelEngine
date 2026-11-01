using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public partial struct GpuColorAttachment
{
    [NativeTypeName("ke_gpu_texture_view")]
    public ulong View;

    [NativeTypeName("ke_gpu_load_op")]
    public global::KernelEngine.Render.GpuLoadOp LoadOp;

    [NativeTypeName("ke_gpu_store_op")]
    public global::KernelEngine.Render.GpuStoreOp StoreOp;

    [NativeTypeName("ke_gpu_clear_value")]
    public GpuClearValue ClearValue;
}
