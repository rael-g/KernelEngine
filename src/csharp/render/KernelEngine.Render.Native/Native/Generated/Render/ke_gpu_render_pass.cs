using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_render_pass
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, ke_gpu_pipeline)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, ulong, void> set_pipeline;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, uint32_t, ke_gpu_bind_group, const uint32_t *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, uint, ulong, uint*, uint, void> set_bind_group;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, uint32_t, ke_gpu_buffer, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, uint, ulong, nuint, void> set_vertex_buffer;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, ke_gpu_buffer, ke_gpu_index_format, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, ulong, global::KernelEngine.Render.GpuIndexFormat, nuint, void> set_index_buffer;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, float, float, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, float, float, float, float, float, float, void> set_viewport;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, int32_t, int32_t, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, int, int, uint, uint, void> set_scissor;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, uint32_t, uint32_t, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, uint, uint, uint, uint, void> draw;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, uint32_t, uint32_t, uint32_t, int32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, uint, uint, uint, int, uint, void> draw_indexed;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, ke_gpu_buffer, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, ulong, nuint, void> draw_indirect;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, void> end;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, sbyte*, void> push_debug_group;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, void> pop_debug_group;

    [NativeTypeName("void (*)(struct ke_gpu_render_pass *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_pass*, sbyte*, void> insert_debug_marker;
}
