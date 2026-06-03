// Default implementation of ke_scene_loader backed by tomlplusplus for parsing
// `.scene.toml` files. The loader walks the [[node]] array, instantiates an
// ECS entity per entry, attaches hierarchy + transform + name components,
// resolves the type through ke_node_type_registry, and forwards properties as
// ke_variant to the registered set_property callback.
//
// Resource-string properties (`"res://..."`) are passed through verbatim as
// KE_VARIANT_STRING — resolution is the consumer binding's job.

#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/world/variant.h>
#include <kernel_engine/kernel/world/world.h>

#include <toml++/toml.hpp>

#include <cmath>
#include <cstring>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{

constexpr float kPi = 3.14159265358979323846f;

struct SceneLoaderImpl
{
    ke_scene_loader        api{};
    ke_allocator          *allocator = nullptr;
    ke_world              *world     = nullptr;
    ke_scene_tree         *tree      = nullptr;
    ke_node_type_registry *registry  = nullptr;
};

// ── TOML → ke_variant ────────────────────────────────────────────────────────

ke_variant toml_to_variant(const toml::node &node)
{
    if (auto b = node.as_boolean()) return ke_variant_bool(b->get());
    if (auto i = node.as_integer()) return ke_variant_int(i->get());
    if (auto d = node.as_floating_point()) return ke_variant_float(d->get());
    if (auto s = node.as_string()) return ke_variant_string(s->get().c_str());
    if (auto arr = node.as_array()) {
        size_t n = arr->size();
        auto get_f = [&](size_t i) -> float {
            const auto &el = (*arr)[i];
            if (auto v = el.value<double>()) return static_cast<float>(*v);
            if (auto v = el.value<int64_t>()) return static_cast<float>(*v);
            return 0.0f;
        };
        if (n == 2) return ke_variant_vec2(get_f(0), get_f(1));
        if (n == 3) return ke_variant_vec3(get_f(0), get_f(1), get_f(2));
        if (n == 4) return ke_variant_vec4(get_f(0), get_f(1), get_f(2), get_f(3));
    }
    return ke_variant_null();
}

// ── Transform helpers ────────────────────────────────────────────────────────

ke_vec3 read_vec3(const toml::array &arr, ke_vec3 fallback)
{
    if (arr.size() < 3) return fallback;
    auto get = [&](size_t i) -> float {
        if (auto v = arr[i].value<double>()) return static_cast<float>(*v);
        if (auto v = arr[i].value<int64_t>()) return static_cast<float>(*v);
        return 0.0f;
    };
    return ke_vec3{get(0), get(1), get(2)};
}

ke_quat read_quat(const toml::array &arr, ke_quat fallback)
{
    if (arr.size() < 4) return fallback;
    auto get = [&](size_t i) -> float {
        if (auto v = arr[i].value<double>()) return static_cast<float>(*v);
        if (auto v = arr[i].value<int64_t>()) return static_cast<float>(*v);
        return 0.0f;
    };
    return ke_quat{get(0), get(1), get(2), get(3)};
}

// Euler → quaternion (degrees, ZYX intrinsic — same convention as
// C# SceneLoader's CreateFromYawPitchRoll(yaw=y, pitch=x, roll=z)).
ke_quat euler_to_quat(const ke_vec3 &deg)
{
    const float kDegToRad = kPi / 180.0f;
    float x = deg.x * kDegToRad * 0.5f;
    float y = deg.y * kDegToRad * 0.5f;
    float z = deg.z * kDegToRad * 0.5f;

    float cx = std::cos(x), sx = std::sin(x);
    float cy = std::cos(y), sy = std::sin(y);
    float cz = std::cos(z), sz = std::sin(z);

    return ke_quat{
        sx * cy * cz - cx * sy * sz,  // x
        cx * sy * cz + sx * cy * sz,  // y
        cx * cy * sz - sx * sy * cz,  // z
        cx * cy * cz + sx * sy * sz,  // w
    };
}

void apply_transform(ke_transform_component &t, const toml::table &xform_tbl)
{
    t.position = ke_vec3{0, 0, 0};
    t.rotation = ke_quat{0, 0, 0, 1};
    t.scale    = ke_vec3{1, 1, 1};

    if (auto p = xform_tbl["position"].as_array()) t.position = read_vec3(*p, t.position);
    if (auto s = xform_tbl["scale"].as_array())    t.scale    = read_vec3(*s, t.scale);
    if (auto r = xform_tbl["rotation"].as_array()) t.rotation = read_quat(*r, t.rotation);
    else if (auto e = xform_tbl["rotation_euler"].as_array()) {
        ke_vec3 euler = read_vec3(*e, ke_vec3{0, 0, 0});
        t.rotation = euler_to_quat(euler);
    }
}

// ── Hierarchy hookup ─────────────────────────────────────────────────────────

void attach_to_parent(ke_ecs_registry *reg, ke_entity entity, ke_entity parent,
                     ke_component_id hcid)
{
    auto *h = static_cast<ke_hierarchy_component *>(
        ke_ecs_component_get(reg, entity, hcid));
    if (!h) return;
    h->parent       = parent;
    h->prev_sibling = KE_ENTITY_INVALID;
    h->next_sibling = KE_ENTITY_INVALID;

    auto *ph = static_cast<ke_hierarchy_component *>(
        ke_ecs_component_get(reg, parent, hcid));
    if (!ph) return;
    if (ph->first_child != KE_ENTITY_INVALID) {
        auto *sib = static_cast<ke_hierarchy_component *>(
            ke_ecs_component_get(reg, ph->first_child, hcid));
        if (sib) sib->prev_sibling = entity;
        h->next_sibling = ph->first_child;
    }
    ph->first_child = entity;
}

// ── Loader core ──────────────────────────────────────────────────────────────

ke_result process_node(SceneLoaderImpl *impl, const toml::table &node_tbl,
                       const std::unordered_map<std::string, ke_entity> &by_name,
                       std::unordered_map<std::string, ke_entity> &out_by_name)
{
    auto name = node_tbl["name"].value<std::string>();
    auto type = node_tbl["type"].value<std::string>();
    if (!name || !type) return KE_ERROR_INVALID_ARGUMENT;

    // Resolve parent entity (root by default).
    ke_entity parent = impl->tree->root(impl->tree);
    if (auto parent_name = node_tbl["parent"].value<std::string>()) {
        auto it = by_name.find(*parent_name);
        if (it == by_name.end()) return KE_ERROR_NOT_FOUND;
        parent = it->second;
    }

    // Allocate ECS entity + universal components.
    auto *reg  = impl->world->get_registry(impl->world);
    auto  hcid = impl->world->hierarchy_id(impl->world);
    auto  ncid = impl->world->name_id(impl->world);
    auto  tcid = impl->world->transform_id(impl->world);

    ke_entity entity = ke_ecs_entity_create(reg);
    if (entity == KE_ENTITY_INVALID) return KE_ERROR_OUT_OF_MEMORY;

    // Hierarchy stays the link-list shape ke_scene_tree expects.
    auto *h = static_cast<ke_hierarchy_component *>(
        ke_ecs_component_add(reg, entity, hcid));
    if (!h) return KE_ERROR_OUT_OF_MEMORY;
    h->parent = h->first_child = h->next_sibling = h->prev_sibling = KE_ENTITY_INVALID;
    attach_to_parent(reg, entity, parent, hcid);

    // Name component — UTF-8, truncated at the 64-byte buffer.
    auto *nc = static_cast<ke_name_component *>(
        ke_ecs_component_add(reg, entity, ncid));
    if (nc) {
        std::strncpy(nc->name, name->c_str(), sizeof(nc->name) - 1);
        nc->name[sizeof(nc->name) - 1] = '\0';
    }

    // Transform component — defaults if no [node.transform] table.
    auto *t = static_cast<ke_transform_component *>(
        ke_ecs_component_add(reg, entity, tcid));
    if (t) {
        if (auto xform = node_tbl["transform"].as_table()) apply_transform(*t, *xform);
        else {
            t->position = ke_vec3{0, 0, 0};
            t->rotation = ke_quat{0, 0, 0, 1};
            t->scale    = ke_vec3{1, 1, 1};
        }
    }

    // Resolve the registered type and fire create().
    const ke_node_type *node_type = nullptr;
    if (impl->registry->lookup(impl->registry, type->c_str(), &node_type) != KE_OK ||
        !node_type || !node_type->create) {
        return KE_ERROR_NOT_FOUND;
    }
    node_type->create(node_type->ctx, entity, name->c_str());

    // Walk [node.properties] and forward each as a ke_variant.
    if (auto props = node_tbl["properties"].as_table()) {
        for (auto &&[k, v] : *props) {
            ke_variant val = toml_to_variant(v);
            if (node_type->set_property) {
                node_type->set_property(node_type->ctx, entity,
                                        std::string(k.str()).c_str(), val);
            }
        }
    }

    out_by_name.emplace(*name, entity);
    return KE_OK;
}

ke_result impl_load(ke_scene_loader *self, const char *path)
{
    if (!self || !self->handle || !path) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<SceneLoaderImpl *>(self->handle);

    toml::table tbl;
    try {
        tbl = toml::parse_file(path);
    } catch (const toml::parse_error &) {
        return KE_ERROR_NOT_FOUND;
    }

    const auto *nodes = tbl["node"].as_array();
    if (!nodes) return KE_OK; // empty scene is valid

    std::unordered_map<std::string, ke_entity> by_name;
    for (const auto &n : *nodes) {
        const auto *node_tbl = n.as_table();
        if (!node_tbl) continue;
        ke_result rc = process_node(impl, *node_tbl, by_name, by_name);
        if (rc != KE_OK) return rc;
    }
    return KE_OK;
}

void impl_destroy(ke_scene_loader *self)
{
    if (!self || !self->handle) return;
    auto *impl = static_cast<SceneLoaderImpl *>(self->handle);
    ke_allocator *alloc = impl->allocator;
    impl->~SceneLoaderImpl();
    alloc->free(alloc, impl);
}

} // namespace

// ── Factory ──────────────────────────────────────────────────────────────────

extern "C" ke_result ke_scene_loader_create(
    ke_allocator           *alloc,
    struct ke_world        *world,
    ke_scene_tree          *tree,
    ke_node_type_registry  *registry,
    ke_scene_loader       **out_loader)
{
    if (!alloc || !world || !tree || !registry || !out_loader)
        return KE_ERROR_INVALID_ARGUMENT;

    void *mem = alloc->alloc(alloc, sizeof(SceneLoaderImpl), alignof(SceneLoaderImpl));
    if (!mem) return KE_ERROR_OUT_OF_MEMORY;
    auto *impl = new (mem) SceneLoaderImpl();
    impl->allocator = alloc;
    impl->world     = world;
    impl->tree      = tree;
    impl->registry  = registry;

    impl->api.handle  = impl;
    impl->api.load    = impl_load;
    impl->api.destroy = impl_destroy;

    *out_loader = &impl->api;
    return KE_OK;
}
