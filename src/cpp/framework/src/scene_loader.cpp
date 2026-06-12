// Default implementation of ke_scene_loader backed by tomlplusplus for parsing
// `.scene.toml` files. The loader walks the [[entity]] array, instantiates an
// ECS entity per entry, attaches hierarchy + transform + name components, writes
// every [entity.components.<name>] block into its matching ECS component via
// ke_ecs_component_apply_variant, and dispatches [entity.script] blocks through
// per-language script factories registered with register_script_language.
//
// Resource-string properties (`"res://..."`) are passed through verbatim as
// KE_VARIANT_STRING — resolution is the consumer binding's job.

#include <kernel_engine/kernel/framework/scene_loader.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/ecs/components.h>
#include <kernel_engine/kernel/ecs/variant.h>
#include <kernel_engine/kernel/ecs/world.h>

#include <toml++/toml.hpp>

#include <cmath>
#include <cstring>
#include <deque>
#include <filesystem>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{

constexpr float kPi = 3.14159265358979323846f;

struct ScriptLanguage
{
    std::string            name;
    ke_script_factory_func factory;
    void                  *ctx;
};

// Per-entity bag of scene-file properties. The arena owns the strings (so the
// component's variant pointers stay valid after the TOML tree is discarded) and
// the entry array itself (whose .data() the component points at).
struct PropertyArena
{
    std::deque<std::string>             strings; // stable .c_str()
    std::vector<ke_variant_table_entry> entries; // stable .data() after fill is done
};

struct SceneLoaderImpl
{
    ke_scene_loader            api{};
    ke_allocator              *allocator = nullptr;
    ke_world                  *world     = nullptr;
    ke_scene_tree             *tree      = nullptr;
    std::string                project_root; // empty = no res:// support; resolution is sibling-relative
    std::vector<ScriptLanguage> script_languages;

    // scene_properties bag — registered once at construction time, attached
    // per entity with an [entity.properties] block. arenas[i] is the storage
    // backing the i-th attachment; freed when the loader is destroyed.
    ke_component_id                              scene_properties_cid = (ke_component_id)-1;
    std::vector<std::unique_ptr<PropertyArena>>  arenas;
};

// ── TOML → ke_variant ────────────────────────────────────────────────────────
//
// Inline TOML tables become KE_VARIANT_TABLE — the recursive case needs stable
// storage for the keys, entry arrays, and child ke_variant_table objects to live
// as long as the outermost variant. VariantArena owns that storage for one
// set_property call.

struct VariantArena
{
    std::deque<std::string>                          strings;     // stable c_str()
    std::deque<std::vector<ke_variant_table_entry>>  entries;     // stable .data()
    std::deque<ke_variant_table>                     tables;      // stable &table
};

ke_variant toml_to_variant(const toml::node &node, VariantArena &arena)
{
    if (auto b = node.as_boolean()) return ke_variant_bool(b->get());
    if (auto i = node.as_integer()) return ke_variant_int(i->get());
    if (auto d = node.as_floating_point()) return ke_variant_float(d->get());
    if (auto s = node.as_string()) {
        arena.strings.emplace_back(s->get());
        return ke_variant_string(arena.strings.back().c_str());
    }
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
    if (auto tbl = node.as_table()) {
        arena.entries.emplace_back();
        auto &entry_vec = arena.entries.back();
        entry_vec.reserve(tbl->size());
        for (auto &&[k, v] : *tbl) {
            arena.strings.emplace_back(k.str());
            entry_vec.push_back({ arena.strings.back().c_str(), toml_to_variant(v, arena) });
        }
        arena.tables.push_back({ static_cast<uint32_t>(entry_vec.size()), entry_vec.data() });
        return ke_variant_table_v(&arena.tables.back());
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

namespace fs = std::filesystem;

// Resolve a nested-scene reference. Supports two shapes:
//   "res://x/y.scene.toml" — prefixed with project_root (when configured)
//   "sibling.toml"         — relative to base_dir
std::string resolve_nested_path(SceneLoaderImpl *impl, const fs::path &base_dir,
                                const std::string &ref)
{
    constexpr const char *prefix = "res://";
    constexpr size_t      plen   = 6;
    if (ref.compare(0, plen, prefix) == 0) {
        if (!impl->project_root.empty()) {
            return (fs::path(impl->project_root) / ref.substr(plen)).string();
        }
        return ref.substr(plen); // fallback: strip prefix, treat as relative cwd
    }
    return (base_dir / ref).string();
}

// Applies an outer entry's transform + properties on top of an already-instantiated
// inner root. Mirrors C# SceneLoader's "first entry of a nested scene takes the
// instancing site's overrides" semantics.
// ── Component-driven (ECS-pure) path ────────────────────────────────────────
//
// Scene files use the `[[entity]]` array: each `[entity.components.X]` table
// resolves by component name in the ECS registry and writes via
// ke_ecs_component_apply_variant. `[entity.script]` dispatches through the
// per-language script factory registered with register_script_language.
// Bindings ship zero per-type decoding code.

ke_result load_entity_scene_recursive(SceneLoaderImpl *impl,
                                      const std::string &path,
                                      ke_entity attach_parent,
                                      const std::string *override_name,
                                      const toml::table *override_outer,
                                      ke_entity *out_root);

// Applies the outer [entity.transform] / [entity.properties] / [entity.script]
// blocks onto a previously-instantiated root, used after a nested-scene load
// to layer the instancing-site overrides on top of the nested defaults.
void apply_entity_overrides(SceneLoaderImpl *impl, ke_entity entity,
                            const toml::table &outer);

ke_result process_entity(SceneLoaderImpl *impl, const fs::path &base_dir,
                         const toml::table &entity_tbl,
                         const std::unordered_map<std::string, ke_entity> &by_name,
                         std::unordered_map<std::string, ke_entity> &out_by_name,
                         ke_entity attach_parent_override,
                         const std::string *override_name,
                         const toml::table *override_outer,
                         ke_entity *out_entity)
{
    auto inner_name = entity_tbl["name"].value<std::string>();
    if (!inner_name && !override_name) return KE_ERROR_INVALID_ARGUMENT;
    const std::string effective_name = override_name ? *override_name : *inner_name;

    // Resolve parent (root unless an explicit `parent = "X"` references a
    // sibling we've already created). Decision #3: flat string reference.
    ke_entity parent = (attach_parent_override != KE_ENTITY_INVALID)
        ? attach_parent_override
        : impl->tree->root(impl->tree);
    if (auto parent_name = entity_tbl["parent"].value<std::string>()) {
        auto it = by_name.find(*parent_name);
        if (it == by_name.end()) return KE_ERROR_NOT_FOUND;
        parent = it->second;
    }

    // Nested-scene branch: `scene = "res://x.scene"` loads x recursively and
    // layers this entry's overrides (name, transform, properties, script) on
    // top of the loaded root. Same shape as the legacy [[node]] scene_ref.
    if (auto scene_ref = entity_tbl["scene"].value<std::string>()) {
        auto resolved = resolve_nested_path(impl, base_dir, *scene_ref);
        ke_entity nested_root = KE_ENTITY_INVALID;
        ke_result rc = load_entity_scene_recursive(impl, resolved, parent,
                                                    &effective_name, &entity_tbl,
                                                    &nested_root);
        if (rc != KE_OK) return rc;
        if (inner_name) out_by_name.emplace(*inner_name, nested_root);
        if (out_entity) *out_entity = nested_root;
        return KE_OK;
    }

    ke_entity entity = impl->tree->create_node(impl->tree, effective_name.c_str(), parent);
    if (entity == KE_ENTITY_INVALID) return KE_ERROR_OUT_OF_MEMORY;

    auto *reg  = impl->world->get_registry(impl->world);
    auto  tcid = impl->world->transform_id(impl->world);

    if (auto xform = entity_tbl["transform"].as_table()) {
        auto *t = static_cast<ke_transform_component *>(
            ke_ecs_component_get(reg, entity, tcid));
        if (t) apply_transform(*t, *xform);
    }

    // [entity.script] — invoke the language-specific factory if one is
    // registered. Game scenes use this for entities backed by a wrapper
    // class (e.g. C# Paddle subclass of KinematicBody2D). The factory does
    // whatever the language needs to bind the wrapper to this entity.
    if (auto script_tbl = entity_tbl["script"].as_table()) {
        auto lang = (*script_tbl)["language"].value<std::string>();
        auto type = (*script_tbl)["type"].value<std::string>();
        if (lang && type) {
            for (auto &sl : impl->script_languages) {
                if (sl.name == *lang && sl.factory) {
                    if (sl.factory(sl.ctx, entity, type->c_str()) != KE_OK) {
                        // Don't abort the whole scene — log-and-skip semantics
                        // match the unknown-component case below.
                    }
                    break;
                }
            }
        }
    }

    // [entity.properties] — generic key/value bag attached as the
    // `scene_properties` component (option C of plan §5b). Bindings read the
    // component the same way they read any other; no per-language callback.
    if (auto props = entity_tbl["properties"].as_table()) {
        auto arena = std::make_unique<PropertyArena>();
        // Reserve to size so push_back below doesn't relocate .data() — the
        // component holds entries.data() and must stay valid post-loop.
        arena->entries.reserve(props->size());
        VariantArena va; // borrows strings from the TOML tree for the variant
                         // construction; we then copy each string into our arena
                         // so the value survives after VariantArena dies.
        for (auto &&[k, v] : *props) {
            ke_variant val = toml_to_variant(v, va);
            arena->strings.emplace_back(k.str());
            const char *key = arena->strings.back().c_str();

            // Strings need to be copied into the arena too — the variant's .s
            // points into VariantArena which dies at the end of this scope.
            if (val.type == KE_VARIANT_STRING && val.s) {
                arena->strings.emplace_back(val.s);
                val.s = arena->strings.back().c_str();
            }
            // KE_VARIANT_TABLE points at VariantArena-owned storage too; we
            // don't deep-copy tables into the bag for now. If a TOML inline
            // table sneaks into [entity.properties] the binding would see a
            // dangling pointer. Decision #4 of §5: tables are forbidden in
            // the new format, so this is consistent.
            if (val.type == KE_VARIANT_TABLE) val.t = nullptr;

            arena->entries.push_back(ke_variant_table_entry{key, val});
        }

        auto *bag = static_cast<ke_scene_properties *>(
            ke_ecs_component_add(reg, entity, impl->scene_properties_cid));
        if (bag) {
            bag->entries = arena->entries.data();
            bag->count   = (uint32_t)arena->entries.size();
        }
        impl->arenas.push_back(std::move(arena));
    }

    if (auto comps = entity_tbl["components"].as_table()) {
        for (auto &&[comp_key, comp_node] : *comps) {
            const auto *comp_tbl = comp_node.as_table();
            if (!comp_tbl) continue;

            ke_component_meta meta{};
            std::string comp_name(comp_key.str());
            if (ke_ecs_component_lookup(reg, comp_name.c_str(), &meta) != KE_OK) {
                // Unknown component name — warning here once we have logging.
                continue;
            }

            ke_ecs_component_add(reg, entity, meta.cid);

            for (auto &&[prop_key, prop_node] : *comp_tbl) {
                VariantArena arena;
                ke_variant val = toml_to_variant(prop_node, arena);
                std::string prop_name(prop_key.str());
                // Ignore the return code: unknown / mismatched fields shouldn't
                // abort the whole load. Future: collect into a diagnostics list.
                (void)ke_ecs_component_apply_variant(reg, entity, meta.cid,
                                                    prop_name.c_str(), &val);
            }
        }
    }

    // Apply outer overrides if this is the root of a nested-scene load (the outer
    // entry's transform/properties/script layer on top of the nested defaults).
    if (override_outer) apply_entity_overrides(impl, entity, *override_outer);

    if (inner_name) out_by_name.emplace(*inner_name, entity);
    if (out_entity) *out_entity = entity;
    return KE_OK;
}

void apply_entity_overrides(SceneLoaderImpl *impl, ke_entity entity,
                            const toml::table &outer)
{
    auto *reg  = impl->world->get_registry(impl->world);
    auto  tcid = impl->world->transform_id(impl->world);

    if (auto xform = outer["transform"].as_table()) {
        auto *t = static_cast<ke_transform_component *>(
            ke_ecs_component_get(reg, entity, tcid));
        if (t) apply_transform(*t, *xform);
    }

    // Outer properties merge into the existing scene_properties bag (or create
    // it if the inner scene had none). Reusing the same per-loader arena keeps
    // memory ownership simple — we just allocate a fresh arena and replace the
    // component pointer with the merged result.
    if (auto props = outer["properties"].as_table()) {
        auto arena = std::make_unique<PropertyArena>();
        arena->entries.reserve(props->size() + 8); // headroom for inner keys

        // Carry over any existing inner keys first, so outer wins on key clash.
        auto *bag = static_cast<ke_scene_properties *>(
            ke_ecs_component_get(reg, entity, impl->scene_properties_cid));
        std::vector<std::string> outer_keys;
        outer_keys.reserve(props->size());
        for (auto &&[k, _] : *props) outer_keys.emplace_back(k.str());
        auto is_overridden = [&](const char *k) {
            for (auto &s : outer_keys) if (s == k) return true;
            return false;
        };
        if (bag) {
            for (uint32_t i = 0; i < bag->count; ++i) {
                const auto &kv = bag->entries[i];
                if (kv.key && is_overridden(kv.key)) continue;
                arena->strings.emplace_back(kv.key);
                const char *kc = arena->strings.back().c_str();
                ke_variant val = kv.value;
                if (val.type == KE_VARIANT_STRING && val.s) {
                    arena->strings.emplace_back(val.s);
                    val.s = arena->strings.back().c_str();
                }
                arena->entries.push_back(ke_variant_table_entry{kc, val});
            }
        }

        VariantArena va;
        for (auto &&[k, v] : *props) {
            ke_variant val = toml_to_variant(v, va);
            arena->strings.emplace_back(k.str());
            const char *kc = arena->strings.back().c_str();
            if (val.type == KE_VARIANT_STRING && val.s) {
                arena->strings.emplace_back(val.s);
                val.s = arena->strings.back().c_str();
            }
            if (val.type == KE_VARIANT_TABLE) val.t = nullptr;
            arena->entries.push_back(ke_variant_table_entry{kc, val});
        }

        if (!bag) {
            bag = static_cast<ke_scene_properties *>(
                ke_ecs_component_add(reg, entity, impl->scene_properties_cid));
        }
        if (bag) {
            bag->entries = arena->entries.data();
            bag->count   = (uint32_t)arena->entries.size();
        }
        impl->arenas.push_back(std::move(arena));
    }

    if (auto script_tbl = outer["script"].as_table()) {
        auto lang = (*script_tbl)["language"].value<std::string>();
        auto type = (*script_tbl)["type"].value<std::string>();
        if (lang && type) {
            for (auto &sl : impl->script_languages) {
                if (sl.name == *lang && sl.factory) {
                    sl.factory(sl.ctx, entity, type->c_str());
                    break;
                }
            }
        }
    }
}

ke_result load_entity_scene_recursive(SceneLoaderImpl *impl,
                                      const std::string &path,
                                      ke_entity attach_parent,
                                      const std::string *override_name,
                                      const toml::table *override_outer,
                                      ke_entity *out_root)
{
    toml::table tbl;
    try { tbl = toml::parse_file(path); }
    catch (const toml::parse_error &) { return KE_ERROR_NOT_FOUND; }

    fs::path base_dir = fs::path(path).parent_path();
    const auto *entities = tbl["entity"].as_array();
    if (!entities) { if (out_root) *out_root = KE_ENTITY_INVALID; return KE_OK; }

    std::unordered_map<std::string, ke_entity> by_name;
    ke_entity root = KE_ENTITY_INVALID;
    bool is_first = true;
    for (const auto &n : *entities) {
        const auto *e_tbl = n.as_table();
        if (!e_tbl) continue;
        ke_entity entity = KE_ENTITY_INVALID;
        ke_result rc;
        if (is_first) {
            rc = process_entity(impl, base_dir, *e_tbl, by_name, by_name,
                                attach_parent, override_name, override_outer, &entity);
            root = entity;
            is_first = false;
        } else {
            rc = process_entity(impl, base_dir, *e_tbl, by_name, by_name,
                                KE_ENTITY_INVALID, nullptr, nullptr, &entity);
        }
        if (rc != KE_OK) return rc;
    }
    if (out_root) *out_root = root;
    return KE_OK;
}

ke_result impl_load(ke_scene_loader *self, const char *path)
{
    if (!self || !self->handle || !path) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<SceneLoaderImpl *>(self->handle);
    return load_entity_scene_recursive(impl, path, KE_ENTITY_INVALID,
                                       nullptr, nullptr, nullptr);
}

ke_result impl_register_script_language(ke_scene_loader *self, const char *language,
                                        ke_script_factory_func factory, void *ctx)
{
    if (!self || !self->handle || !language || !factory) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<SceneLoaderImpl *>(self->handle);
    // Re-registration replaces (so tests / multiple init flows are idempotent).
    for (auto &sl : impl->script_languages) {
        if (sl.name == language) { sl.factory = factory; sl.ctx = ctx; return KE_OK; }
    }
    impl->script_languages.push_back({ language, factory, ctx });
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
    const char             *project_root,
    ke_scene_loader       **out_loader)
{
    if (!alloc || !world || !tree || !out_loader)
        return KE_ERROR_INVALID_ARGUMENT;

    void *mem = alloc->alloc(alloc, sizeof(SceneLoaderImpl), alignof(SceneLoaderImpl));
    if (!mem) return KE_ERROR_OUT_OF_MEMORY;
    auto *impl = new (mem) SceneLoaderImpl();
    impl->allocator    = alloc;
    impl->world        = world;
    impl->tree         = tree;
    if (project_root) impl->project_root = project_root;

    impl->api.handle                   = impl;
    impl->api.load                     = impl_load;
    impl->api.register_script_language = impl_register_script_language;
    impl->api.destroy                  = impl_destroy;

    // Register the scene_properties bag component once at construction time
    // so every [entity.properties] block lands as a real ECS component.
    impl->scene_properties_cid = ke_ecs_component_register_v2(
        impl->world->get_registry(impl->world),
        KE_SCENE_PROPERTIES_COMPONENT_NAME,
        sizeof(ke_scene_properties),
        nullptr, 0); // No SceneLoader-writable fields — bindings read the
                     // entries array directly via ke_ecs_component_get.

    *out_loader = &impl->api;
    return KE_OK;
}
