using System.Numerics;

using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.View.Native;

public unsafe partial struct ke_view_space
{
    public void* handle;

    [NativeTypeName("ke_view_space_params (*)(struct ke_view_space *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, ke_view_space_params> @params;

    [NativeTypeName("void (*)(struct ke_view_space *, const ke_vec3 *, const ke_vec3 *, const ke_vec3 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, System.Numerics.Vector3*, System.Numerics.Vector3*, System.Numerics.Vector3*, System.Numerics.Matrix4x4*, void> look_to;

    [NativeTypeName("void (*)(struct ke_view_space *, const ke_vec3 *, const ke_vec3 *, const ke_vec3 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, System.Numerics.Vector3*, System.Numerics.Vector3*, System.Numerics.Vector3*, System.Numerics.Matrix4x4*, void> look_at;

    [NativeTypeName("void (*)(struct ke_view_space *, const ke_mat4 *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, System.Numerics.Matrix4x4*, System.Numerics.Matrix4x4*, void> view_from_transform;

    [NativeTypeName("void (*)(struct ke_view_space *, float, float, float, float, const ke_ndc_convention *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, float, float, float, float, global::KernelEngine.Render.NdcConvention*, System.Numerics.Matrix4x4*, void> perspective;

    [NativeTypeName("void (*)(struct ke_view_space *, float, float, float, float, const ke_ndc_convention *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, float, float, float, float, global::KernelEngine.Render.NdcConvention*, System.Numerics.Matrix4x4*, void> orthographic;
}
