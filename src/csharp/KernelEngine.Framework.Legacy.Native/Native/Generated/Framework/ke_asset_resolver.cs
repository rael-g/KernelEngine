namespace KernelEngine.Framework.Legacy.Native;

public unsafe partial struct ke_asset_resolver
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_texture_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_texture_data**, ke_result> resolve_texture;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_texture_data*, void> free_texture;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_mesh_shape_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_mesh_shape_data*, ke_result> resolve_mesh;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_mesh_shape_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_mesh_shape_data*, void> free_mesh;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_material_spec *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_material_spec*, ke_result> resolve_material;

    [NativeTypeName("void (*)(struct ke_asset_resolver *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, void> destroy;
}
