using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_render_target
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_gpu_render_target *, ke_gpu_texture_view *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, ulong*, KernelEngine.Result.Native.ke_result> acquire;

    [NativeTypeName("ke_result (*)(struct ke_gpu_render_target *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, KernelEngine.Result.Native.ke_result> present;

    [NativeTypeName("void (*)(struct ke_gpu_render_target *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, uint*, uint*, void> size;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_gpu_render_target *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, ke_gpu_texture_format> format;
}
