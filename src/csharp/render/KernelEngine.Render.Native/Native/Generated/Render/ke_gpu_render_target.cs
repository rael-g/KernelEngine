using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_render_target
{
    public void* handle;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_gpu_render_target *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, KernelEngine.Common.Native.ke_error**, ulong> acquire;

    [NativeTypeName("bool (*)(struct ke_gpu_render_target *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, KernelEngine.Common.Native.ke_error**, bool> present;

    [NativeTypeName("void (*)(struct ke_gpu_render_target *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, uint*, uint*, void> size;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_gpu_render_target *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_render_target*, ke_gpu_texture_format> format;
}
