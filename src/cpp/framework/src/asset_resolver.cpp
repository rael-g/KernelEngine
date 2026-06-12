// Asset resolver — maps path strings (res:// or absolute) to typed CPU-side
// asset data. The image loader is injected via factory (no direct link to
// stb_image or any other concrete plugin); a future model-loader injection
// will round out resolve_mesh for .gltf/.fbx/.obj files.

#include <kernel_engine/kernel/framework/asset_resolver.h>
#include <kernel_engine/framework/asset_resolver_create.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <new>
#include <string>

namespace fs = std::filesystem;

namespace
{

struct AssetResolverImpl
{
    ke_asset_resolver  api{};
    ke_allocator      *allocator    = nullptr;
    ke_image_loader   *image_loader = nullptr;
    std::string        project_root;
};

// Resolve a path of the supported shapes into a filesystem path.
//   res://x → project_root + x   (empty project_root → strip prefix, treat as CWD)
//   anything else → returned as-is
std::string resolve_path(AssetResolverImpl *impl, const char *path)
{
    constexpr const char *prefix = "res://";
    constexpr size_t      plen   = 6;
    std::string p(path);
    if (p.compare(0, plen, prefix) == 0) {
        std::string remainder = p.substr(plen);
        if (!impl->project_root.empty()) {
            return (fs::path(impl->project_root) / remainder).string();
        }
        return remainder;
    }
    return p;
}

std::string lowercase_extension(const std::string &path)
{
    auto dot = path.find_last_of('.');
    if (dot == std::string::npos) return "";
    std::string ext = path.substr(dot);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return ext;
}

// ── Texture resolution ──────────────────────────────────────────────────────

ke_result impl_resolve_texture(ke_asset_resolver *self, const char *path,
                                ke_texture_data **out)
{
    if (!self || !self->handle || !path || !out) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<AssetResolverImpl *>(self->handle);
    if (!impl->image_loader) return KE_ERROR_INVALID_ARGUMENT;

    auto resolved = resolve_path(impl, path);
    if (!fs::exists(resolved)) return KE_ERROR_NOT_FOUND;

    return impl->image_loader->load_image(impl->image_loader, resolved.c_str(), out);
}

void impl_free_texture(ke_asset_resolver *self, ke_texture_data *data)
{
    if (!self || !self->handle || !data) return;
    auto *impl = static_cast<AssetResolverImpl *>(self->handle);
    if (impl->image_loader && impl->image_loader->free_image) {
        impl->image_loader->free_image(impl->image_loader, data);
    }
}

// ── Mesh resolution ─────────────────────────────────────────────────────────

ke_result impl_resolve_mesh(ke_asset_resolver *self, const char *path,
                             ke_mesh_shape_data *out)
{
    if (!self || !self->handle || !path || !out) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<AssetResolverImpl *>(self->handle);

    std::string p(path);
    // Built-in primitives: res://primitives/{quad|plane|cube|sphere}
    constexpr const char *prim_prefix = "res://primitives/";
    constexpr size_t      pp_len      = 17;
    if (p.compare(0, pp_len, prim_prefix) == 0) {
        std::string name = p.substr(pp_len);
        ke_mesh_primitive kind;
        if      (name == "quad")   kind = KE_MESH_PRIMITIVE_QUAD;
        else if (name == "plane")  kind = KE_MESH_PRIMITIVE_PLANE;
        else if (name == "cube")   kind = KE_MESH_PRIMITIVE_CUBE;
        else if (name == "sphere") kind = KE_MESH_PRIMITIVE_SPHERE;
        else return KE_ERROR_NOT_FOUND;
        return ke_mesh_shape_bake(impl->allocator, kind, 0, out);
    }
    // Future: dispatch .gltf/.fbx/.obj via an injected ke_asset_loader.
    return KE_ERROR_NOT_FOUND;
}

void impl_free_mesh(ke_asset_resolver *self, ke_mesh_shape_data *data)
{
    if (!self || !self->handle || !data) return;
    auto *impl = static_cast<AssetResolverImpl *>(self->handle);
    ke_mesh_shape_free(impl->allocator, data);
}

// ── Material resolution ────────────────────────────────────────────────────

ke_result impl_resolve_material(ke_asset_resolver *self, const char *path,
                                 ke_material_spec *out)
{
    if (!self || !self->handle || !path || !out) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<AssetResolverImpl *>(self->handle);
    auto resolved = resolve_path(impl, path);
    return ke_material_file_parse(resolved.c_str(), out);
}

// ── Lifecycle ──────────────────────────────────────────────────────────────

void impl_destroy(ke_asset_resolver *self)
{
    if (!self || !self->handle) return;
    auto *impl = static_cast<AssetResolverImpl *>(self->handle);
    ke_allocator *alloc = impl->allocator;
    impl->~AssetResolverImpl();
    alloc->free(alloc, impl);
}

} // namespace

extern "C" ke_result ke_asset_resolver_create(
    ke_allocator       *alloc,
    ke_image_loader    *image_loader,
    const char         *project_root,
    ke_asset_resolver **out)
{
    if (!alloc || !out) return KE_ERROR_INVALID_ARGUMENT;
    void *mem = alloc->alloc(alloc, sizeof(AssetResolverImpl), alignof(AssetResolverImpl));
    if (!mem) return KE_ERROR_OUT_OF_MEMORY;
    auto *impl = new (mem) AssetResolverImpl();
    impl->allocator    = alloc;
    impl->image_loader = image_loader;
    if (project_root) impl->project_root = project_root;

    impl->api.handle           = impl;
    impl->api.resolve_texture  = impl_resolve_texture;
    impl->api.free_texture     = impl_free_texture;
    impl->api.resolve_mesh     = impl_resolve_mesh;
    impl->api.free_mesh        = impl_free_mesh;
    impl->api.resolve_material = impl_resolve_material;
    impl->api.destroy          = impl_destroy;

    *out = &impl->api;
    return KE_OK;
}
