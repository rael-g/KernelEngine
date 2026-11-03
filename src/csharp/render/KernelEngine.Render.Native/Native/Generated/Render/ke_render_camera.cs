using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_camera
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_mat4 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, System.Numerics.Matrix4x4*, System.Numerics.Matrix4x4*, void> view;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_mat4 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, System.Numerics.Matrix4x4*, System.Numerics.Matrix4x4*, void> view_rotation;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_camera_component *, float, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, global::KernelEngine.Render.CameraComponent*, float, System.Numerics.Matrix4x4*, void> projection;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_camera_component *, float, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, global::KernelEngine.Render.CameraComponent*, float, System.Numerics.Matrix4x4*, void> perspective_projection;

    [NativeTypeName("void (*)(struct ke_render_camera *, const ke_camera_component *, float, ke_camera_frustum *)")]
    public delegate* unmanaged[Cdecl]<ke_render_camera*, global::KernelEngine.Render.CameraComponent*, float, global::KernelEngine.Render.CameraFrustum*, void> perspective_frustum;
}
