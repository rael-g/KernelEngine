using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_camera
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_mat4 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, KernelEngine.Common.Native.ke_mat4*, KernelEngine.Common.Native.ke_mat4*, void> view;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_mat4 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, KernelEngine.Common.Native.ke_mat4*, KernelEngine.Common.Native.ke_mat4*, void> view_rotation;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_camera_component *, float, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, ke_camera_component*, float, KernelEngine.Common.Native.ke_mat4*, void> projection;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_camera_component *, float, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, ke_camera_component*, float, KernelEngine.Common.Native.ke_mat4*, void> perspective_projection;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_camera_component *, float, ke_camera_frustum *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, ke_camera_component*, float, ke_camera_frustum*, void> perspective_frustum;
}
