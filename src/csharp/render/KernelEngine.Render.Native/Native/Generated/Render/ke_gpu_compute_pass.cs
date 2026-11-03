using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_compute_pass
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *, ke_gpu_pipeline)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, ulong, void> set_pipeline;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *, uint32_t, ke_gpu_bind_group, const uint32_t *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, uint, ulong, uint*, uint, void> set_bind_group;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *, uint32_t, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, uint, uint, uint, void> dispatch;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *, ke_gpu_buffer, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, ulong, nuint, void> dispatch_indirect;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, void> end;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, sbyte*, void> push_debug_group;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, void> pop_debug_group;

    [NativeTypeName("void (*)(struct ke_gpu_compute_pass *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_compute_pass*, sbyte*, void> insert_debug_marker;
}
