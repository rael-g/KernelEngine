#include <kernel_engine/framework/mesh_asset_system.h>
#include <kernel_engine/framework/mesh_render_system.h>
#include <kernel_engine/framework/mesh_shape.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/render/texture.h>
#include <kernel_engine/kernel/render/mesh.h>

#include <cstring>
#include <new>
#include <string>
#include <unordered_map>
#include <unordered_set>

// ── Internal state ───────────────────────────────────────────────────────────
//
// The asset system keeps a per-primitive mesh handle cache (one bake per
// primitive name, shared across every entity that requests it) and a per-
// entity processed set (so we don't re-bake or re-create a material for an
// entity whose primitive + color we already resolved). Materials are created
// per entity, not deduped — colour combinations are cheap to make and the
// alternative is a colour-keyed cache that'd grow with every distinct shade.

struct ke_mesh_asset_system
{
    ke_world         *world;
    ke_allocator     *allocator;
    ke_render        *render;
    ke_ecs_registry  *registry;
    ke_component_id   mesh_cid;
    uint32_t          reads[1];

    std::unordered_map<std::string, ke_mesh_handle> mesh_cache;
    std::unordered_set<uint64_t>                    processed_entities;
};

static int prim_id_from_name(const char *name)
{
    if (!name) return -1;
    if (std::strcmp(name, "cube")   == 0) return KE_MESH_PRIMITIVE_CUBE;
    if (std::strcmp(name, "plane")  == 0) return KE_MESH_PRIMITIVE_PLANE;
    if (std::strcmp(name, "quad")   == 0) return KE_MESH_PRIMITIVE_QUAD;
    if (std::strcmp(name, "sphere") == 0) return KE_MESH_PRIMITIVE_SPHERE;
    return -1;
}

static ke_mesh_handle bake_or_get(ke_mesh_asset_system *self, const char *prim_name)
{
    auto it = self->mesh_cache.find(prim_name);
    if (it != self->mesh_cache.end()) return it->second;

    int prim = prim_id_from_name(prim_name);
    if (prim < 0) return KE_MESH_NONE;

    ke_mesh_shape_data shape{};
    if (ke_mesh_shape_bake(self->allocator, (ke_mesh_primitive)prim, 0, &shape) != KE_OK)
        return KE_MESH_NONE;

    ke_mesh_handle handle{};
    ke_result rc = self->render->create_mesh(self->render,
        shape.vertices, shape.vertex_count, shape.indices, shape.index_count, &handle);
    ke_mesh_shape_free(self->allocator, &shape);
    if (rc != KE_OK) return KE_MESH_NONE;

    self->mesh_cache.emplace(prim_name, handle);
    return handle;
}

static ke_material_handle make_material(ke_mesh_asset_system *self, const float *color)
{
    ke_material mat{};
    mat.r = color[0]; mat.g = color[1]; mat.b = color[2]; mat.a = color[3];
    mat.albedo     = ke_texture_handle{0}; // built-in white
    mat.metallic   = 0.0f;
    mat.roughness  = 0.7f;
    mat.normal_map = KE_TEXTURE_NONE;
    ke_material_handle h{};
    if (self->render->create_material(self->render, &mat, &h) != KE_OK)
        return KE_MATERIAL_NONE;
    return h;
}

static void mesh_asset_update(void *handle, ke_world * /*world*/, float /*dt*/,
                              ke_frame_packet * /*packet*/)
{
    auto *self = static_cast<ke_mesh_asset_system *>(handle);
    if (!self->render) return;

    ke_entity *entities = nullptr;
    void      *data     = nullptr;
    size_t     count    = 0;
    ke_ecs_registry_query(self->registry, self->mesh_cid, &entities, &data, &count);
    if (count == 0) return;

    auto *comps = static_cast<ke_mesh_component *>(data);
    for (size_t i = 0; i < count; ++i) {
        ke_entity e = entities[i];
        if (self->processed_entities.count(e)) continue;

        ke_mesh_component &c = comps[i];

        // We use the processed_entities set (not mesh.idx) as the sentinel for
        // "already baked" because ke_ecs_component_add zero-inits the struct,
        // which makes mesh.idx == 0 (a legitimate handle for the built-in white
        // mesh, not a "needs bake" marker).
        if (c.primitive[0] != '\0') {
            ke_mesh_handle h = bake_or_get(self, c.primitive);
            if (h.idx != KE_HANDLE_NONE) c.mesh = h;
        }

        // Material: alpha == 0 means "no color was supplied" (zero-init result).
        // Built-in white (handle 0) stays as the fallback in that case.
        if (c.color[3] > 0.0f) {
            ke_material_handle m = make_material(self, c.color);
            if (m.idx != KE_HANDLE_NONE) c.material = m;
        }

        // Mark processed even if a step failed: spamming bake on a typo every
        // frame burns CPU. Hot-reload eventually clears this set.
        self->processed_entities.insert(e);
    }
}

extern "C" ke_result ke_mesh_asset_system_create(
    const ke_mesh_asset_system_params *params,
    ke_mesh_asset_system             **out_system)
{
    if (!params || !params->world || !params->allocator || !params->render ||
        !params->mesh_system || !out_system) {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_ecs_registry *registry = params->world->get_registry(params->world);
    if (!registry) return KE_ERROR_NOT_INITIALIZED;

    auto *self = static_cast<ke_mesh_asset_system *>(
        params->allocator->alloc(params->allocator, sizeof(ke_mesh_asset_system), 0));
    if (!self) return KE_ERROR_OUT_OF_MEMORY;
    new (self) ke_mesh_asset_system{};

    self->world      = params->world;
    self->allocator  = params->allocator;
    self->render     = params->render;
    self->registry   = registry;
    self->mesh_cid   = ke_mesh_render_system_component_id(params->mesh_system);
    self->reads[0]   = self->mesh_cid;

    *out_system = self;
    return KE_OK;
}

extern "C" void ke_mesh_asset_system_destroy(ke_mesh_asset_system *system)
{
    if (!system) return;
    ke_allocator *alloc = system->allocator;
    ke_render    *r     = system->render;
    for (auto &kv : system->mesh_cache) {
        if (r) r->destroy_mesh(r, kv.second);
    }
    system->~ke_mesh_asset_system();
    alloc->free(alloc, system);
}

extern "C" void ke_mesh_asset_system_get_system_params(
    ke_mesh_asset_system *system, ke_system_params *out_params)
{
    if (!out_params) return;
    *out_params = ke_system_params{};
    if (!system) return;
    out_params->name        = "ke_mesh_asset_system";
    out_params->update      = mesh_asset_update;
    out_params->handle      = system;
    out_params->reads       = system->reads;
    out_params->read_count  = 1;
    out_params->writes      = system->reads; // also mutates the same component
    out_params->write_count = 1;
}
