#include <stddef.h>
#include <kernel_engine/asset/asset_resolver.h>
const unsigned long long layout_values[] = {
    sizeof(ke_asset_resolver),
    offsetof(ke_asset_resolver, handle),
    offsetof(ke_asset_resolver, resolve_texture),
    offsetof(ke_asset_resolver, free_texture),
    offsetof(ke_asset_resolver, resolve_mesh),
    offsetof(ke_asset_resolver, free_mesh),
    offsetof(ke_asset_resolver, resolve_material),
    offsetof(ke_asset_resolver, resolve_font),
    offsetof(ke_asset_resolver, free_font),
    offsetof(ke_asset_resolver, resolve_texture_into),
    offsetof(ke_asset_resolver, resolve_mesh_into),
    offsetof(ke_asset_resolver, resolve_material_into),
    offsetof(ke_asset_resolver, resolve_path),
    sizeof(ke_asset_resolver_handle),
    offsetof(ke_asset_resolver_handle, ref),
    offsetof(ke_asset_resolver_handle, destroy),
    0,
};
