using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_assets
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_render_assets *, const char *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_assets*, sbyte*, global::KernelEngine.Render.TextureHandle*, KernelEngine.Result.Native.Result> resolve_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_assets *, const char *, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_assets*, sbyte*, global::KernelEngine.Render.MeshHandle*, KernelEngine.Result.Native.Result> resolve_mesh;

    [NativeTypeName("ke_result (*)(struct ke_render_assets *, const char *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_assets*, sbyte*, global::KernelEngine.Render.MaterialHandle*, KernelEngine.Result.Native.Result> resolve_material;
}
