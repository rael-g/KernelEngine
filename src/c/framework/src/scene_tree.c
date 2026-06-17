// ke_scene_tree impl — pure C. Owns the cids of the framework's three
// scene-graph components (transform/hierarchy/name) registered against the
// caller-supplied ke_ecs. All hierarchy bookkeeping flows through ECS
// component reads/writes; no separate side state.

#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/framework/components.h>
#include <kernel_engine/ecs/ke_ecs.h>

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// ── Internal state ──────────────────────────────────────────────────────────

typedef struct scene_tree_state {
    ke_scene_tree    api;
    ke_ecs          *ecs;          // borrowed
    ke_allocator    *allocator;    // borrowed
    ke_entity        root;
    ke_component_id  transform_cid;
    ke_component_id  hierarchy_cid;
    ke_component_id  name_cid;
} scene_tree_state;

// ── Helpers ─────────────────────────────────────────────────────────────────

static ke_hierarchy_component *get_hierarchy(scene_tree_state *s, ke_entity e) {
    return (ke_hierarchy_component *)s->ecs->component_get(s->ecs, e, s->hierarchy_cid);
}

static const ke_name_component *get_name(scene_tree_state *s, ke_entity e) {
    return (const ke_name_component *)s->ecs->component_get(s->ecs, e, s->name_cid);
}

// Resolves or registers a component cid by name.
static ke_component_id ensure_component(ke_ecs *ecs, const char *name, size_t size) {
    ke_component_meta meta;
    if (ecs->component_lookup(ecs, name, &meta, NULL) == KE_OK) return meta.cid;
    return ecs->component_register(ecs, name, size);
}

// ── vtable: root ────────────────────────────────────────────────────────────

static ke_entity vt_root(ke_scene_tree *self) {
    if (!self || !self->handle) return KE_ENTITY_INVALID;
    return ((scene_tree_state *)self->handle)->root;
}

// ── vtable: create_node ─────────────────────────────────────────────────────

static ke_entity vt_create_node(ke_scene_tree *self, const char *name, ke_entity parent) {
    if (!self || !self->handle) return KE_ENTITY_INVALID;
    scene_tree_state *s = (scene_tree_state *)self->handle;
    if (parent == KE_ENTITY_INVALID) parent = s->root;

    ke_entity entity = s->ecs->entity_create(s->ecs);
    if (entity == KE_ENTITY_INVALID) return KE_ENTITY_INVALID;

    // Add all three components FIRST so the entity's archetype is stable. Each
    // component_add in flecs can move the entity to a new archetype and
    // invalidate any pointer captured from an earlier add — only after all
    // adds are done can we safely fetch + write the field data.
    if (!s->ecs->component_add(s->ecs, entity, s->transform_cid) ||
        !s->ecs->component_add(s->ecs, entity, s->hierarchy_cid) ||
        !s->ecs->component_add(s->ecs, entity, s->name_cid)) {
        s->ecs->entity_destroy(s->ecs, entity);
        return KE_ENTITY_INVALID;
    }

    ke_transform_component *t = (ke_transform_component *)s->ecs->component_get(
        s->ecs, entity, s->transform_cid);
    if (t) {
        t->position = (ke_vec3){ 0.0f, 0.0f, 0.0f };
        t->rotation = (ke_quat){ 0.0f, 0.0f, 0.0f, 1.0f };
        t->scale    = (ke_vec3){ 1.0f, 1.0f, 1.0f };
        for (int i = 0; i < 16; ++i) t->world_matrix.m[i] = (i % 5 == 0) ? 1.0f : 0.0f;
    }

    ke_hierarchy_component *h = get_hierarchy(s, entity);
    h->parent       = parent;
    h->first_child  = KE_ENTITY_INVALID;
    h->next_sibling = KE_ENTITY_INVALID;
    h->prev_sibling = KE_ENTITY_INVALID;

    ke_name_component *n = (ke_name_component *)s->ecs->component_get(
        s->ecs, entity, s->name_cid);
    if (n) {
        if (name && *name) {
            size_t len = 0;
            while (name[len] && len < sizeof(n->name) - 1) { n->name[len] = name[len]; ++len; }
            n->name[len] = '\0';
        } else {
            n->name[0] = '\0';
        }
    }

    // Prepend into parent's child list (doubly-linked, O(1)).
    // Re-fetch h: the sibling fixup may need fresh pointers (touching the
    // parent doesn't move our archetype, but defensive re-reads cost nothing).
    h = get_hierarchy(s, entity);
    ke_hierarchy_component *ph = get_hierarchy(s, parent);
    if (ph && h) {
        h->next_sibling = ph->first_child;
        if (ph->first_child != KE_ENTITY_INVALID) {
            ke_hierarchy_component *sib = get_hierarchy(s, ph->first_child);
            if (sib) sib->prev_sibling = entity;
        }
        ph->first_child = entity;
    }

    return entity;
}

// ── vtable: find_node ───────────────────────────────────────────────────────

static bool name_equals_segment(const ke_name_component *name, const char *seg, size_t len) {
    if (!name) return false;
    size_t n = 0;
    while (n < sizeof(name->name) && name->name[n]) ++n;
    if (n != len) return false;
    return strncmp(name->name, seg, len) == 0;
}

static ke_entity find_by_name(scene_tree_state *s, ke_entity parent,
                               const char *target, size_t target_len) {
    ke_hierarchy_component *h = get_hierarchy(s, parent);
    if (!h) return KE_ENTITY_INVALID;
    for (ke_entity c = h->first_child; c != KE_ENTITY_INVALID; ) {
        const ke_name_component *cn = get_name(s, c);
        if (name_equals_segment(cn, target, target_len)) return c;
        ke_entity found = find_by_name(s, c, target, target_len);
        if (found != KE_ENTITY_INVALID) return found;
        ke_hierarchy_component *ch = get_hierarchy(s, c);
        c = ch ? ch->next_sibling : KE_ENTITY_INVALID;
    }
    return KE_ENTITY_INVALID;
}

static ke_entity child_by_segment(scene_tree_state *s, ke_entity parent,
                                   const char *seg, size_t len) {
    ke_hierarchy_component *h = get_hierarchy(s, parent);
    if (!h) return KE_ENTITY_INVALID;
    for (ke_entity c = h->first_child; c != KE_ENTITY_INVALID; ) {
        const ke_name_component *cn = get_name(s, c);
        if (name_equals_segment(cn, seg, len)) return c;
        ke_hierarchy_component *ch = get_hierarchy(s, c);
        c = ch ? ch->next_sibling : KE_ENTITY_INVALID;
    }
    return KE_ENTITY_INVALID;
}

static ke_entity vt_find_node(ke_scene_tree *self, const char *name_or_path) {
    if (!self || !self->handle || !name_or_path || !name_or_path[0])
        return KE_ENTITY_INVALID;
    scene_tree_state *s = (scene_tree_state *)self->handle;

    bool is_path = strchr(name_or_path, '/') != NULL;
    if (!is_path) return find_by_name(s, s->root, name_or_path, strlen(name_or_path));

    const char *p = name_or_path;
    while (*p == '/' || *p == '.') p++;

    ke_entity current = s->root;
    while (*p && current != KE_ENTITY_INVALID) {
        const char *seg_start = p;
        while (*p && *p != '/') p++;
        size_t seg_len = (size_t)(p - seg_start);
        if (seg_len == 0) { if (*p == '/') p++; continue; }
        current = child_by_segment(s, current, seg_start, seg_len);
        if (*p == '/') p++;
    }
    return current;
}

// ── vtable: destroy_node / destroy_all ──────────────────────────────────────

static void destroy_entities_recursive(scene_tree_state *s, ke_entity e) {
    ke_hierarchy_component *h = get_hierarchy(s, e);
    if (h) {
        ke_entity c = h->first_child;
        while (c != KE_ENTITY_INVALID) {
            ke_hierarchy_component *ch = get_hierarchy(s, c);
            ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
            destroy_entities_recursive(s, c);
            c = next;
        }
    }
    s->ecs->entity_destroy(s->ecs, e);
}

static ke_result vt_destroy_node(ke_scene_tree *self, ke_entity entity, ke_error **out_error) {
    if (!self || !self->handle || entity == KE_ENTITY_INVALID)
        return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    scene_tree_state *s = (scene_tree_state *)self->handle;

    if (!get_hierarchy(s, entity)) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "entity not found");

    // Detach from parent's child list before tearing the subtree down.
    // Snapshot the navigation fields up-front because the subsequent
    // get_hierarchy calls (for parent + siblings) may move flecs archetypes
    // and invalidate `h`.
    ke_hierarchy_component *h = get_hierarchy(s, entity);
    ke_entity h_prev = h->prev_sibling, h_next = h->next_sibling, h_parent = h->parent;
    if (h_parent != KE_ENTITY_INVALID) {
        ke_hierarchy_component *ph = get_hierarchy(s, h_parent);
        if (ph) {
            if (ph->first_child == entity) ph->first_child = h_next;
        }
        if (h_prev != KE_ENTITY_INVALID) {
            ke_hierarchy_component *prev = get_hierarchy(s, h_prev);
            if (prev) prev->next_sibling = h_next;
        }
        if (h_next != KE_ENTITY_INVALID) {
            ke_hierarchy_component *next = get_hierarchy(s, h_next);
            if (next) next->prev_sibling = h_prev;
        }
    }

    destroy_entities_recursive(s, entity);
    return KE_OK;
}

static void vt_destroy_all(ke_scene_tree *self) {
    if (!self || !self->handle) return;
    scene_tree_state *s = (scene_tree_state *)self->handle;

    // Destroy every child of root; root itself stays so the tree remains usable.
    ke_hierarchy_component *rh = get_hierarchy(s, s->root);
    if (!rh) return;
    ke_entity c = rh->first_child;
    while (c != KE_ENTITY_INVALID) {
        ke_hierarchy_component *ch = get_hierarchy(s, c);
        ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
        destroy_entities_recursive(s, c);
        c = next;
    }
    rh->first_child = KE_ENTITY_INVALID;
}

// ── vtable: propagate_transforms ────────────────────────────────────────────

static void propagate_recursive(scene_tree_state *s, ke_entity entity,
                                const ke_mat4 *parent_world)
{
    ke_transform_component *t = (ke_transform_component *)s->ecs->component_get(
        s->ecs, entity, s->transform_cid);

    const ke_mat4 *child_parent = parent_world;
    if (t) {
        ke_mat4 local;
        ke_mat4_from_transform(&local, &t->position, &t->rotation, &t->scale);
        ke_mat4_mul(&t->world_matrix, &local, parent_world);
        child_parent = &t->world_matrix;
    }

    ke_hierarchy_component *h = get_hierarchy(s, entity);
    if (!h) return;
    for (ke_entity c = h->first_child; c != KE_ENTITY_INVALID; ) {
        ke_hierarchy_component *ch = get_hierarchy(s, c);
        ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
        propagate_recursive(s, c, child_parent);
        c = next;
    }
}

static void vt_propagate_transforms(ke_scene_tree *self) {
    if (!self || !self->handle) return;
    scene_tree_state *s = (scene_tree_state *)self->handle;
    ke_mat4 identity;
    for (int i = 0; i < 16; ++i) identity.m[i] = (i % 5 == 0) ? 1.0f : 0.0f;
    ke_hierarchy_component *rh = get_hierarchy(s, s->root);
    if (!rh) return;
    for (ke_entity c = rh->first_child; c != KE_ENTITY_INVALID; ) {
        ke_hierarchy_component *ch = get_hierarchy(s, c);
        ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
        propagate_recursive(s, c, &identity);
        c = next;
    }
}

// ── vtable: teardown ────────────────────────────────────────────────────────

static void vt_destroy(ke_scene_tree *self) {
    if (!self || !self->handle) return;
    scene_tree_state *s = (scene_tree_state *)self->handle;
    // Destroy root + everything under it.
    destroy_entities_recursive(s, s->root);
    ke_allocator *a = s->allocator;
    a->free(a, s);
    a->destroy(a);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_scene_tree_create(ke_ecs *ecs, ke_scene_tree **out_tree, ke_error **out_error) {
    if (!ecs || !out_tree) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

    ke_allocator *alloc = ke_allocator_malloc_create();
    if (!alloc) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "allocator creation failed");

    scene_tree_state *s = (scene_tree_state *)alloc->alloc(
        alloc, sizeof(scene_tree_state), 8);
    if (!s) { alloc->destroy(alloc); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed"); }
    memset(s, 0, sizeof(*s));

    s->ecs       = ecs;
    s->allocator = alloc;
    s->transform_cid = ensure_component(ecs, KE_COMPONENT_NAME_TRANSFORM, sizeof(ke_transform_component));
    s->hierarchy_cid = ensure_component(ecs, KE_COMPONENT_NAME_HIERARCHY, sizeof(ke_hierarchy_component));
    s->name_cid      = ensure_component(ecs, KE_COMPONENT_NAME_NAME,      sizeof(ke_name_component));

    // Spin up root entity with the standard components.
    s->root = ecs->entity_create(ecs);
    if (s->root == KE_ENTITY_INVALID) {
        alloc->free(alloc, s);
        alloc->destroy(alloc);
        return KE_ERROR;
    }
    // Add all components FIRST, then fetch + populate. Each add can move the
    // entity to a new archetype and invalidate pointers from earlier adds.
    if (!ecs->component_add(ecs, s->root, s->hierarchy_cid) ||
        !ecs->component_add(ecs, s->root, s->name_cid)) {
        ecs->entity_destroy(ecs, s->root);
        alloc->free(alloc, s);
        alloc->destroy(alloc);
        return KE_ERROR;
    }

    ke_hierarchy_component *h = (ke_hierarchy_component *)ecs->component_get(ecs, s->root, s->hierarchy_cid);
    h->parent       = KE_ENTITY_INVALID;
    h->first_child  = KE_ENTITY_INVALID;
    h->next_sibling = KE_ENTITY_INVALID;
    h->prev_sibling = KE_ENTITY_INVALID;

    ke_name_component *n = (ke_name_component *)ecs->component_get(ecs, s->root, s->name_cid);
    if (n) {
        const char *root_name = "Root";
        size_t len = 0;
        while (root_name[len] && len < sizeof(n->name) - 1) { n->name[len] = root_name[len]; ++len; }
        n->name[len] = '\0';
    }

    s->api.handle                = s;
    s->api.root                  = vt_root;
    s->api.create_node           = vt_create_node;
    s->api.destroy_node          = vt_destroy_node;
    s->api.destroy_all           = vt_destroy_all;
    s->api.find_node             = vt_find_node;
    s->api.propagate_transforms  = vt_propagate_transforms;
    s->api.destroy               = vt_destroy;

    *out_tree = &s->api;
    return KE_OK;
}
