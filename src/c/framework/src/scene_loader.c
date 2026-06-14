// ke_scene_loader impl — pure C, tomlc99 backed.
//
// Walks a `.scene.toml` file:
//   [[entity]] entries → tree.create_node + transform/components apply + script
//   factory dispatch + properties bag.
//
// [entity.components.X] uses the world's apply registry: lookup cid by name,
// add the component, build a variant-table entry list from the TOML table,
// call the registered apply_fn. Components without a registered apply are
// silently skipped (binding warning path lands when we have logging).
//
// scene_properties lifetime: every per-entity arena (strings + entries) is
// pushed onto an internal list, freed at loader destroy. Per B1 Tier 3 the
// arena is owned by the world conceptually (it outlives the entity), but
// implementationally the loader keeps them parked in its own list until
// destroy — same end behavior, simpler ownership graph.

#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/kernel/framework/world.h>
#include <kernel_engine/kernel/framework/scene_tree.h>
#include <kernel_engine/kernel/framework/components.h>

#include "../third_party/tomlc99/toml.h"

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Script factory (single slot) ────────────────────────────────────────────

// ── Arena (per-loader, freed at destroy) ────────────────────────────────────
//
// Backs scene_properties components and the variant entries they point to.
// Chunked bump-style: each chunk is a fixed-size buffer; out-of-space
// requests allocate a fresh chunk. Survives the TOML tree's lifetime.

#define ARENA_CHUNK_SIZE (16 * 1024)
typedef struct arena_chunk {
    struct arena_chunk *next;
    uint8_t            *data;
    size_t              used;
    size_t              cap;
} arena_chunk;

typedef struct loader_state {
    ke_scene_loader        api;
    ke_allocator          *allocator;
    struct ke_world       *world;
    char                   project_root[512];

    ke_script_factory_func script_factory;
    void                  *script_ctx;

    ke_component_id        scene_properties_cid;

    arena_chunk           *arena_head;
} loader_state;

// ── Arena ops ───────────────────────────────────────────────────────────────

static void *arena_alloc(loader_state *s, size_t bytes, size_t align) {
    arena_chunk *c = s->arena_head;
    size_t a = align ? align : 8;

    if (c) {
        size_t pad = (a - (((uintptr_t)c->data + c->used) % a)) % a;
        if (c->used + pad + bytes <= c->cap) {
            void *p = c->data + c->used + pad;
            c->used += pad + bytes;
            return p;
        }
    }

    size_t want = bytes < ARENA_CHUNK_SIZE ? ARENA_CHUNK_SIZE : bytes;
    arena_chunk *nc = (arena_chunk *)s->allocator->alloc(
        s->allocator, sizeof(arena_chunk) + want, 8);
    if (!nc) return NULL;
    nc->data = (uint8_t *)nc + sizeof(arena_chunk);
    nc->cap  = want;
    nc->used = bytes;
    nc->next = s->arena_head;
    s->arena_head = nc;
    return nc->data;
}

static char *arena_strdup(loader_state *s, const char *src) {
    if (!src) return NULL;
    size_t n = strlen(src);
    char *out = (char *)arena_alloc(s, n + 1, 1);
    if (!out) return NULL;
    memcpy(out, src, n);
    out[n] = '\0';
    return out;
}

static void arena_destroy(loader_state *s) {
    arena_chunk *c = s->arena_head;
    while (c) {
        arena_chunk *nx = c->next;
        s->allocator->free(s->allocator, c);
        c = nx;
    }
    s->arena_head = NULL;
}

// ── TOML → variant ──────────────────────────────────────────────────────────

// Converts a tomlc99 node (passed indirectly via toml_table_t + key OR
// toml_array_t + index) into a ke_variant. Strings + nested tables stay
// arena-owned (caller-side arena passed in).

static ke_variant toml_value_to_variant(loader_state *s,
                                         const char *typed_str,
                                         bool has_str,
                                         int64_t i, bool has_int,
                                         double d, bool has_double,
                                         int b, bool has_bool,
                                         toml_array_t *arr,
                                         toml_table_t *tbl) {
    if (has_bool) return ke_variant_bool(b != 0);
    if (has_int)  return ke_variant_int(i);
    if (has_double) return ke_variant_float(d);
    if (has_str)  return ke_variant_string(arena_strdup(s, typed_str));
    if (arr) {
        int n = toml_array_nelem(arr);
        float comps[4] = {0, 0, 0, 0};
        int len = n > 4 ? 4 : n;
        for (int k = 0; k < len; ++k) {
            toml_datum_t v = toml_double_at(arr, k);
            if (v.ok) { comps[k] = (float)v.u.d; continue; }
            toml_datum_t vi = toml_int_at(arr, k);
            if (vi.ok) comps[k] = (float)vi.u.i;
        }
        if (n == 2) return ke_variant_vec2(comps[0], comps[1]);
        if (n == 3) return ke_variant_vec3(comps[0], comps[1], comps[2]);
        if (n >= 4) return ke_variant_vec4(comps[0], comps[1], comps[2], comps[3]);
        return ke_variant_null();
    }
    if (tbl) {
        // Inline TOML tables: convert recursively, copy strings + nested
        // tables into the arena. Nested table support is best-effort —
        // depth-1 inline-tables are the typical case ([entity.properties]
        // already lives inside a table, no infinite recursion expected).
        int n = toml_table_nkval(tbl) + toml_table_ntab(tbl) + toml_table_narr(tbl);
        ke_variant_table_entry *entries =
            (ke_variant_table_entry *)arena_alloc(s, sizeof(ke_variant_table_entry) * n, 8);
        ke_variant_table *vtbl = (ke_variant_table *)arena_alloc(s, sizeof(ke_variant_table), 8);
        if (!entries || !vtbl) return ke_variant_null();
        int count = 0;
        for (int k = 0; ; ++k) {
            const char *key = toml_key_in(tbl, k);
            if (!key) break;
            // Read child value through the right typed accessor.
            ke_variant child = ke_variant_null();
            toml_datum_t ds = toml_string_in(tbl, key); if (ds.ok) { child = ke_variant_string(arena_strdup(s, ds.u.s)); free(ds.u.s); goto store; }
            toml_datum_t di = toml_int_in(tbl, key);    if (di.ok) { child = ke_variant_int(di.u.i); goto store; }
            toml_datum_t dd = toml_double_in(tbl, key); if (dd.ok) { child = ke_variant_float(dd.u.d); goto store; }
            toml_datum_t db = toml_bool_in(tbl, key);   if (db.ok) { child = ke_variant_bool(db.u.b != 0); goto store; }
            { toml_array_t *ca = toml_array_in(tbl, key); if (ca) { child = toml_value_to_variant(s, NULL, false, 0, false, 0, false, 0, false, ca, NULL); goto store; } }
            { toml_table_t *ct = toml_table_in(tbl, key); if (ct) { child = toml_value_to_variant(s, NULL, false, 0, false, 0, false, 0, false, NULL, ct); /* fallthrough */ } }
        store:
            entries[count].key   = arena_strdup(s, key);
            entries[count].value = child;
            count++;
        }
        vtbl->count   = (uint32_t)count;
        vtbl->entries = entries;
        return ke_variant_table_v(vtbl);
    }
    return ke_variant_null();
}

// Convenience: read a value identified by key in a table → variant.
static ke_variant read_var_in(loader_state *s, toml_table_t *tbl, const char *key) {
    toml_datum_t ds = toml_string_in(tbl, key);
    if (ds.ok) {
        ke_variant v = ke_variant_string(arena_strdup(s, ds.u.s));
        free(ds.u.s);
        return v;
    }
    toml_datum_t di = toml_int_in(tbl, key);
    if (di.ok) return ke_variant_int(di.u.i);
    toml_datum_t dd = toml_double_in(tbl, key);
    if (dd.ok) return ke_variant_float(dd.u.d);
    toml_datum_t db = toml_bool_in(tbl, key);
    if (db.ok) return ke_variant_bool(db.u.b != 0);
    toml_array_t *ca = toml_array_in(tbl, key);
    if (ca) return toml_value_to_variant(s, NULL, false, 0, false, 0, false, 0, false, ca, NULL);
    toml_table_t *ct = toml_table_in(tbl, key);
    if (ct) return toml_value_to_variant(s, NULL, false, 0, false, 0, false, 0, false, NULL, ct);
    return ke_variant_null();
}

// ── Path resolution ────────────────────────────────────────────────────────

static void path_dirname(const char *path, char *out, size_t cap) {
    if (cap == 0) return;
    const char *last = NULL;
    for (const char *p = path; *p; ++p) {
        if (*p == '/' || *p == '\\') last = p;
    }
    if (!last) { out[0] = '.'; out[1] = '\0'; return; }
    size_t n = (size_t)(last - path);
    if (n >= cap) n = cap - 1;
    memcpy(out, path, n);
    out[n] = '\0';
}

static void resolve_path(const loader_state *s, const char *base_dir,
                          const char *ref, char *out, size_t cap) {
    if (strncmp(ref, "res://", 6) == 0) {
        const char *rest = ref + 6;
        if (s->project_root[0]) {
            snprintf(out, cap, "%s/%s", s->project_root, rest);
        } else {
            snprintf(out, cap, "%s", rest);
        }
        return;
    }
    if (ref[0] == '/' || (ref[0] && ref[1] == ':')) {
        snprintf(out, cap, "%s", ref);
        return;
    }
    snprintf(out, cap, "%s/%s", base_dir, ref);
}

// ── Script dispatch ────────────────────────────────────────────────────────

static void dispatch_script(loader_state *s, ke_entity entity, const char *type_name) {
    if (s->script_factory) s->script_factory(s->script_ctx, entity, type_name);
}

// ── Properties bag ─────────────────────────────────────────────────────────

static void attach_properties(loader_state *s, ke_entity entity, toml_table_t *props_tbl) {
    ke_ecs *e = s->world->ecs(s->world);

    int nk = toml_table_nkval(props_tbl) + toml_table_narr(props_tbl) + toml_table_ntab(props_tbl);
    if (nk == 0) return;

    ke_variant_table_entry *entries =
        (ke_variant_table_entry *)arena_alloc(s, sizeof(ke_variant_table_entry) * nk, 8);
    if (!entries) return;
    int count = 0;
    for (int k = 0; ; ++k) {
        const char *key = toml_key_in(props_tbl, k);
        if (!key) break;
        entries[count].key   = arena_strdup(s, key);
        entries[count].value = read_var_in(s, props_tbl, key);
        count++;
    }

    void *comp = e->component_add(e, entity, s->scene_properties_cid);
    if (!comp) return;
    ke_scene_properties *bag = (ke_scene_properties *)comp;
    bag->entries = entries;
    bag->count   = (uint32_t)count;
}

// ── Components application via apply registry ──────────────────────────────

static void apply_component_block(loader_state *s, ke_entity entity,
                                   const char *comp_name, toml_table_t *comp_tbl) {
    ke_ecs *e = s->world->ecs(s->world);

    ke_component_meta meta;
    if (e->component_lookup(e, comp_name, &meta) != KE_OK) return;  // unknown component; skip

    void *comp = e->component_add(e, entity, meta.cid);
    if (!comp) return;

    ke_component_apply_fn apply = s->world->get_component_apply(s->world, meta.cid);
    if (!apply) return;  // no apply registered → skip the property mapping

    int nk = toml_table_nkval(comp_tbl) + toml_table_narr(comp_tbl) + toml_table_ntab(comp_tbl);
    if (nk == 0) return;

    // Stack-allocated entry list — bounded by TOML key count per block, which
    // is small in practice. If a future scene file pushes past 32 fields per
    // component block we can fall back to arena alloc; until then the stack
    // path keeps per-call cost zero.
    ke_variant_table_entry entries[32];
    int max = nk > 32 ? 32 : nk;
    int count = 0;
    for (int k = 0; k < max && count < 32; ++k) {
        const char *key = toml_key_in(comp_tbl, k);
        if (!key) break;
        entries[count].key   = arena_strdup(s, key);  // arena: variants may point at arena strings
        entries[count].value = read_var_in(s, comp_tbl, key);
        count++;
    }
    apply(comp, entries, (uint32_t)count);
}

// ── Transform helper ──────────────────────────────────────────────────────

static void apply_transform_block(loader_state *s, ke_entity entity, toml_table_t *xform_tbl) {
    // Treat [entity.transform] as sugar for [entity.components.transform].
    apply_component_block(s, entity, KE_COMPONENT_NAME_TRANSFORM, xform_tbl);
}

// ── Entity processing ─────────────────────────────────────────────────────

typedef struct named_entity {
    char       name[64];
    ke_entity  entity;
} named_entity;

static ke_result load_scene_recursive(loader_state *s, const char *path,
                                       ke_entity attach_parent,
                                       const char *override_name,
                                       toml_table_t *override_outer,
                                       ke_entity *out_root);

static void apply_outer_overrides(loader_state *s, ke_entity entity, toml_table_t *outer) {
    toml_table_t *xt = toml_table_in(outer, "transform");
    if (xt) apply_transform_block(s, entity, xt);
    toml_table_t *props = toml_table_in(outer, "properties");
    if (props) attach_properties(s, entity, props);
    toml_datum_t type_d = toml_string_in(outer, "type");
    if (type_d.ok) { dispatch_script(s, entity, type_d.u.s); free(type_d.u.s); }
    toml_table_t *comps = toml_table_in(outer, "components");
    if (comps) {
        for (int i = 0; ; ++i) {
            const char *cn = toml_key_in(comps, i);
            if (!cn) break;
            toml_table_t *ct = toml_table_in(comps, cn);
            if (ct) apply_component_block(s, entity, cn, ct);
        }
    }
}

static ke_result process_entity(loader_state *s, const char *base_dir,
                                 toml_table_t *entity_tbl,
                                 named_entity *by_name, uint32_t *by_name_count,
                                 uint32_t by_name_cap,
                                 ke_entity attach_parent_override,
                                 const char *override_name,
                                 toml_table_t *override_outer,
                                 ke_entity *out_entity) {
    toml_datum_t name_d = toml_string_in(entity_tbl, "name");
    if (!name_d.ok && !override_name) return KE_ERROR_INVALID_ARGUMENT;
    const char *effective_name = override_name ? override_name : name_d.u.s;

    struct ke_scene_tree *tree = s->world->scene_tree(s->world);
    ke_entity parent = (attach_parent_override != KE_ENTITY_INVALID)
        ? attach_parent_override : tree->root(tree);

    toml_datum_t pn = toml_string_in(entity_tbl, "parent");
    if (pn.ok) {
        ke_entity found = KE_ENTITY_INVALID;
        for (uint32_t i = 0; i < *by_name_count; ++i) {
            if (strcmp(by_name[i].name, pn.u.s) == 0) { found = by_name[i].entity; break; }
        }
        free(pn.u.s);
        if (found == KE_ENTITY_INVALID) {
            if (name_d.ok) free(name_d.u.s);
            return KE_ERROR_NOT_FOUND;
        }
        parent = found;
    }

    toml_datum_t scene_ref = toml_string_in(entity_tbl, "scene");
    if (scene_ref.ok) {
        char resolved[1024];
        resolve_path(s, base_dir, scene_ref.u.s, resolved, sizeof(resolved));
        free(scene_ref.u.s);
        ke_entity nested_root = KE_ENTITY_INVALID;
        ke_result rc = load_scene_recursive(s, resolved, parent,
                                            effective_name, entity_tbl, &nested_root);
        if (rc != KE_OK) { if (name_d.ok) free(name_d.u.s); return rc; }
        if (name_d.ok && *by_name_count < by_name_cap) {
            named_entity *ne = &by_name[(*by_name_count)++];
            copy_name_init: {
                size_t ln = strlen(name_d.u.s);
                if (ln >= sizeof(ne->name)) ln = sizeof(ne->name) - 1;
                memcpy(ne->name, name_d.u.s, ln);
                ne->name[ln] = '\0';
            }
            ne->entity = nested_root;
        }
        if (out_entity) *out_entity = nested_root;
        if (name_d.ok) free(name_d.u.s);
        return KE_OK;
    }

    ke_entity entity = tree->create_node(tree, effective_name, parent);
    if (entity == KE_ENTITY_INVALID) { if (name_d.ok) free(name_d.u.s); return KE_ERROR_OUT_OF_MEMORY; }

    toml_table_t *xform_tbl = toml_table_in(entity_tbl, "transform");
    if (xform_tbl) apply_transform_block(s, entity, xform_tbl);

    toml_datum_t type_d = toml_string_in(entity_tbl, "type");
    if (type_d.ok) { dispatch_script(s, entity, type_d.u.s); free(type_d.u.s); }

    toml_table_t *props_tbl = toml_table_in(entity_tbl, "properties");
    if (props_tbl) attach_properties(s, entity, props_tbl);

    toml_table_t *comps_tbl = toml_table_in(entity_tbl, "components");
    if (comps_tbl) {
        for (int i = 0; ; ++i) {
            const char *cn = toml_key_in(comps_tbl, i);
            if (!cn) break;
            toml_table_t *ct = toml_table_in(comps_tbl, cn);
            if (ct) apply_component_block(s, entity, cn, ct);
        }
    }

    if (override_outer) apply_outer_overrides(s, entity, override_outer);

    if (name_d.ok && *by_name_count < by_name_cap) {
        named_entity *ne = &by_name[(*by_name_count)++];
        size_t ln = strlen(name_d.u.s);
        if (ln >= sizeof(ne->name)) ln = sizeof(ne->name) - 1;
        memcpy(ne->name, name_d.u.s, ln);
        ne->name[ln] = '\0';
        ne->entity = entity;
    }
    if (out_entity) *out_entity = entity;
    if (name_d.ok) free(name_d.u.s);
    return KE_OK;
}

static ke_result load_scene_recursive(loader_state *s, const char *path,
                                       ke_entity attach_parent,
                                       const char *override_name,
                                       toml_table_t *override_outer,
                                       ke_entity *out_root) {
    FILE *fp = fopen(path, "rb");
    if (!fp) return KE_ERROR_NOT_FOUND;
    char errbuf[200];
    toml_table_t *root = toml_parse_file(fp, errbuf, sizeof(errbuf));
    fclose(fp);
    if (!root) return KE_ERROR_NOT_FOUND;

    char base_dir[512];
    path_dirname(path, base_dir, sizeof(base_dir));

    toml_array_t *entities = toml_array_in(root, "entity");
    if (!entities) { if (out_root) *out_root = KE_ENTITY_INVALID; toml_free(root); return KE_OK; }

    enum { NAME_CAP = 256 };
    named_entity by_name[NAME_CAP];
    uint32_t by_name_count = 0;

    ke_entity first_root = KE_ENTITY_INVALID;
    int n = toml_array_nelem(entities);
    bool is_first = true;
    for (int i = 0; i < n; ++i) {
        toml_table_t *et = toml_table_at(entities, i);
        if (!et) continue;
        ke_entity ent = KE_ENTITY_INVALID;
        ke_result rc;
        if (is_first) {
            rc = process_entity(s, base_dir, et, by_name, &by_name_count, NAME_CAP,
                                attach_parent, override_name, override_outer, &ent);
            first_root = ent;
            is_first = false;
        } else {
            rc = process_entity(s, base_dir, et, by_name, &by_name_count, NAME_CAP,
                                KE_ENTITY_INVALID, NULL, NULL, &ent);
        }
        if (rc != KE_OK) { toml_free(root); return rc; }
    }

    if (out_root) *out_root = first_root;
    toml_free(root);
    return KE_OK;
}

// ── vtable ────────────────────────────────────────────────────────────────

static ke_result vt_load(ke_scene_loader *self, const char *path) {
    if (!self || !self->handle || !path) return KE_ERROR_INVALID_ARGUMENT;
    loader_state *s = (loader_state *)self->handle;
    return load_scene_recursive(s, path, KE_ENTITY_INVALID, NULL, NULL, NULL);
}

static ke_result vt_register_script_factory(ke_scene_loader *self,
                                             ke_script_factory_func factory,
                                             void *ctx) {
    if (!self || !self->handle || !factory) return KE_ERROR_INVALID_ARGUMENT;
    loader_state *s = (loader_state *)self->handle;
    s->script_factory = factory;
    s->script_ctx     = ctx;
    return KE_OK;
}

static void vt_destroy(ke_scene_loader *self) {
    if (!self || !self->handle) return;
    loader_state *s = (loader_state *)self->handle;
    arena_destroy(s);
    ke_allocator *a = s->allocator;
    a->free(a, s);
}

// ── Factory ───────────────────────────────────────────────────────────────

ke_result ke_scene_loader_create(ke_allocator *alloc, struct ke_world *world,
                                  const char *project_root, ke_scene_loader **out_loader) {
    if (!alloc || !world || !out_loader) return KE_ERROR_INVALID_ARGUMENT;

    loader_state *s = (loader_state *)alloc->alloc(alloc, sizeof(loader_state), 8);
    if (!s) return KE_ERROR_OUT_OF_MEMORY;
    memset(s, 0, sizeof(*s));
    s->allocator = alloc;
    s->world     = world;
    if (project_root) {
        size_t n = strlen(project_root);
        if (n >= sizeof(s->project_root)) n = sizeof(s->project_root) - 1;
        memcpy(s->project_root, project_root, n);
        s->project_root[n] = '\0';
    }

    // scene_properties cid: register via the world's ecs. The component has
    // no apply callback because its layout (entries pointer + count) is
    // populated directly by attach_properties, not field-by-field.
    ke_ecs *e = world->ecs(world);
    ke_component_meta meta;
    if (e->component_lookup(e, KE_SCENE_PROPERTIES_COMPONENT_NAME, &meta) == KE_OK) {
        s->scene_properties_cid = meta.cid;
    } else {
        s->scene_properties_cid = e->component_register(
            e, KE_SCENE_PROPERTIES_COMPONENT_NAME, sizeof(ke_scene_properties));
    }

    s->api.handle                  = s;
    s->api.load                    = vt_load;
    s->api.register_script_factory = vt_register_script_factory;
    s->api.destroy                 = vt_destroy;

    *out_loader = &s->api;
    return KE_OK;
}
