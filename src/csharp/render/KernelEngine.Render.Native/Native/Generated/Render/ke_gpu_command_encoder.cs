using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_command_encoder
{
    public void* handle;

    [NativeTypeName("struct ke_gpu_render_pass *(*)(struct ke_gpu_command_encoder *, const ke_gpu_render_pass_params *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ke_gpu_render_pass_params*, ke_gpu_render_pass*> begin_render_pass;

    [NativeTypeName("struct ke_gpu_compute_pass *(*)(struct ke_gpu_command_encoder *, const ke_gpu_compute_pass_params *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ke_gpu_compute_pass_params*, ke_gpu_compute_pass*> begin_compute_pass;

    [NativeTypeName("void (*)(struct ke_gpu_command_encoder *, ke_gpu_buffer, size_t, ke_gpu_buffer, size_t, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ulong, nuint, ulong, nuint, nuint, void> copy_buffer_to_buffer;

    [NativeTypeName("ke_result (*)(struct ke_gpu_command_encoder *, ke_gpu_buffer, size_t, uint32_t, ke_gpu_texture, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ulong, nuint, uint, ulong, uint, uint, uint, uint, uint, KernelEngine.Result.Native.Result> copy_buffer_to_texture;

    [NativeTypeName("void (*)(struct ke_gpu_command_encoder *, ke_gpu_texture, ke_gpu_texture, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ulong, ulong, uint, uint, void> copy_texture_to_texture;

    [NativeTypeName("ke_result (*)(struct ke_gpu_command_encoder *, ke_gpu_command_buffer_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ke_gpu_command_buffer_handle*, KernelEngine.Result.Native.Result> finish;

    [NativeTypeName("ke_result (*)(struct ke_gpu_command_encoder *, ke_gpu_texture, uint32_t, uint32_t, uint32_t, ke_gpu_buffer, size_t, uint32_t, uint32_t, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, ulong, uint, uint, uint, ulong, nuint, uint, uint, uint, KernelEngine.Result.Native.Result> copy_texture_to_buffer;

    [NativeTypeName("void (*)(struct ke_gpu_command_encoder *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, sbyte*, void> push_debug_group;

    [NativeTypeName("void (*)(struct ke_gpu_command_encoder *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, void> pop_debug_group;

    [NativeTypeName("void (*)(struct ke_gpu_command_encoder *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, sbyte*, void> insert_debug_marker;
}
