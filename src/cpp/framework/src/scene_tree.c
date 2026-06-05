#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/components.h>
#include <string.h>
#include <stdlib.h>

// ── Internal state ────────────────────────────────────────────────────────────

typedef struct ke_scene_tree_impl
{
    ke_scene_tree     api;
    ke_world         *world;
    ke_allocator     *allocator;
    ke_ecs_registry  *registry;
    ke_entity         root;
    ke_component_id   transform_cid;
    ke_component_id   hierarchy_cid;
    ke_component_id   name_cid;
} ke_scene_tree_impl;

// ── Hierarchy helpers (ECS-backed) ────────────────────────────────────────────

static ke_hierarchy_component *get_hierarchy(ke_scene_tree_impl *impl, ke_entity e)
{
    return (ke_hierarchy_component *)ke_ecs_component_get(
        impl->registry, e, impl->hierarchy_cid);
}

static const ke_name_component *get_name(ke_scene_tree_impl *impl, ke_entity e)
{
    return (const ke_name_component *)ke_ecs_component_get(
        impl->registry, e, impl->name_cid);
}

// ── vtable: root ──────────────────────────────────────────────────────────────

static ke_entity tree_root(ke_scene_tree *self)
{
    if (!self || !self->handle) return KE_ENTITY_INVALID;
    return ((ke_scene_tree_impl *)self->handle)->root;
}

// ── vtable: create_node ───────────────────────────────────────────────────────
//
// Ported 1:1 from C# Tree.CreateEntityWithHierarchy: spin up an ECS entity,
// attach Transform (origin, identity, unit scale), Hierarchy, and Name, then
// prepend the new node into the parent's first_child list in O(1).

static ke_entity tree_create_node(ke_scene_tree *self, const char *name, ke_entity parent)
{
    if (!self || !self->handle) return KE_ENTITY_INVALID;
    ke_scene_tree_impl *impl = (ke_scene_tree_impl *)self->handle;
    if (parent == KE_ENTITY_INVALID) parent = impl->root;

    ke_entity entity = ke_ecs_entity_create(impl->registry);
    if (entity == KE_ENTITY_INVALID) return KE_ENTITY_INVALID;

    ke_transform_component *t = (ke_transform_component *)ke_ecs_component_add(
        impl->registry, entity, impl->transform_cid);
    if (t) {
        t->position = (ke_vec3){ 0.0f, 0.0f, 0.0f };
        t->rotation = (ke_quat){ 0.0f, 0.0f, 0.0f, 1.0f };
        t->scale    = (ke_vec3){ 1.0f, 1.0f, 1.0f };
        // world_matrix is overwritten by the TransformSystem each tick; identity is fine.
        for (int i = 0; i < 16; ++i) t->world_matrix.m[i] = (i % 5 == 0) ? 1.0f : 0.0f;
    }

    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_add(
        impl->registry, entity, impl->hierarchy_cid);
    if (!h) {
        ke_ecs_entity_destroy(impl->registry, entity);
        return KE_ENTITY_INVALID;
    }
    h->parent       = parent;
    h->first_child  = KE_ENTITY_INVALID;
    h->next_sibling = KE_ENTITY_INVALID;
    h->prev_sibling = KE_ENTITY_INVALID;

    ke_name_component *n = (ke_name_component *)ke_ecs_component_add(
        impl->registry, entity, impl->name_cid);
    if (n) {
        if (name && *name) {
            // Copy up to 63 bytes; NameComponent is fixed 64 chars (last byte is the null terminator).
            size_t len = 0;
            while (name[len] && len < sizeof(n->name) - 1) { n->name[len] = name[len]; ++len; }
            n->name[len] = '\0';
        } else {
            n->name[0] = '\0';
        }
    }

    // Prepend into parent's first_child list (doubly-linked, O(1)).
    ke_hierarchy_component *ph = get_hierarchy(impl, parent);
    if (ph) {
        h->next_sibling = ph->first_child;
        if (ph->first_child != KE_ENTITY_INVALID) {
            ke_hierarchy_component *sib = get_hierarchy(impl, ph->first_child);
            if (sib) sib->prev_sibling = entity;
        }
        ph->first_child = entity;
    }

    return entity;
}

// ── vtable: find_node ─────────────────────────────────────────────────────────

// Compare a component name with a substring (segment from a path), no allocation.
static bool name_equals_segment(const ke_name_component *name,
                                const char *seg, size_t len)
{
    if (!name) return false;
    if (strnlen(name->name, sizeof(name->name)) != len) return false;
    return strncmp(name->name, seg, len) == 0;
}

// Pre-order recursive search by name. Returns the FIRST match found in DFS order.
static ke_entity find_by_name(ke_scene_tree_impl *impl,
                              ke_entity parent,
                              const char *target,
                              size_t target_len)
{
    ke_hierarchy_component *h = get_hierarchy(impl, parent);
    if (!h) return KE_ENTITY_INVALID;
    for (ke_entity c = h->first_child; c != KE_ENTITY_INVALID; ) {
        const ke_name_component *cn = get_name(impl, c);
        if (name_equals_segment(cn, target, target_len)) return c;
        ke_entity found = find_by_name(impl, c, target, target_len);
        if (found != KE_ENTITY_INVALID) return found;
        ke_hierarchy_component *ch = get_hierarchy(impl, c);
        c = ch ? ch->next_sibling : KE_ENTITY_INVALID;
    }
    return KE_ENTITY_INVALID;
}

// Looks for a direct child of `parent` whose name matches the segment.
static ke_entity child_by_segment(ke_scene_tree_impl *impl,
                                  ke_entity parent,
                                  const char *seg, size_t len)
{
    ke_hierarchy_component *h = get_hierarchy(impl, parent);
    if (!h) return KE_ENTITY_INVALID;
    for (ke_entity c = h->first_child; c != KE_ENTITY_INVALID; ) {
        const ke_name_component *cn = get_name(impl, c);
        if (name_equals_segment(cn, seg, len)) return c;
        ke_hierarchy_component *ch = get_hierarchy(impl, c);
        c = ch ? ch->next_sibling : KE_ENTITY_INVALID;
    }
    return KE_ENTITY_INVALID;
}

static ke_entity tree_find_node(ke_scene_tree *self, const char *name_or_path)
{
    if (!self || !self->handle || !name_or_path || !name_or_path[0])
        return KE_ENTITY_INVALID;
    ke_scene_tree_impl *impl = (ke_scene_tree_impl *)self->handle;

    bool is_path = strchr(name_or_path, '/') != NULL;
    if (!is_path)
        return find_by_name(impl, impl->root, name_or_path, strlen(name_or_path));

    // Path navigation. Leading '/' or './' anchors at root; everything else
    // walks segment-by-segment from root too (relative-from-root is the only
    // sensible interpretation in a single-root tree).
    const char *p = name_or_path;
    while (*p == '/' || *p == '.') p++;

    ke_entity current = impl->root;
    while (*p && current != KE_ENTITY_INVALID) {
        const char *seg_start = p;
        while (*p && *p != '/') p++;
        size_t seg_len = (size_t)(p - seg_start);
        if (seg_len == 0) { if (*p == '/') p++; continue; }
        current = child_by_segment(impl, current, seg_start, seg_len);
        if (*p == '/') p++;
    }
    return current;
}

// ── vtable: destroy_node / destroy_all ────────────────────────────────────────

// Post-order walk: visits children before the entity itself, mirroring the
// Tree.cs `TickDestroyRecursive` semantics so the on_destroy callback can still
// read the parent's state.
static void notify_recursive(ke_scene_tree_impl *impl, ke_entity e)
{
    ke_hierarchy_component *h = get_hierarchy(impl, e);
    if (h) {
        ke_entity c = h->first_child;
        while (c != KE_ENTITY_INVALID) {
            ke_hierarchy_component *ch = get_hierarchy(impl, c);
            ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
            notify_recursive(impl, c);
            c = next;
        }
    }
    ke_world_notify_destroy(impl->world, e);
}

// Frees ECS entities post-order. Separate pass because destroying an entity
// invalidates its hierarchy component pointer; we already fired all
// on_destroy hooks first, so the order of the structural teardown only needs
// to keep child pointers valid up to the moment we visit them.
static void destroy_entities_recursive(ke_scene_tree_impl *impl, ke_entity e)
{
    ke_hierarchy_component *h = get_hierarchy(impl, e);
    if (h) {
        ke_entity c = h->first_child;
        while (c != KE_ENTITY_INVALID) {
            ke_hierarchy_component *ch = get_hierarchy(impl, c);
            ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
            destroy_entities_recursive(impl, c);
            c = next;
        }
    }
    ke_ecs_entity_destroy(impl->registry, e);
}

static ke_result tree_destroy_node(ke_scene_tree *self, ke_entity entity)
{
    if (!self || !self->handle || entity == KE_ENTITY_INVALID)
        return KE_ERROR_INVALID_ARGUMENT;
    ke_scene_tree_impl *impl = (ke_scene_tree_impl *)self->handle;

    // Verify the entity is at least known to this world. Lacking a hierarchy
    // component is a strong signal it's not part of the tree (anything created
    // through this contract has one).
    if (!get_hierarchy(impl, entity)) return KE_ERROR_NOT_FOUND;

    // Detach from parent's child list (if any) so the parent stays consistent
    // after we tear the subtree down.
    ke_hierarchy_component *h = get_hierarchy(impl, entity);
    if (h && h->parent != KE_ENTITY_INVALID) {
        ke_hierarchy_component *ph = get_hierarchy(impl, h->parent);
        if (ph) {
            if (ph->first_child == entity) ph->first_child = h->next_sibling;
            if (h->prev_sibling != KE_ENTITY_INVALID) {
                ke_hierarchy_component *prev = get_hierarchy(impl, h->prev_sibling);
                if (prev) prev->next_sibling = h->next_sibling;
            }
            if (h->next_sibling != KE_ENTITY_INVALID) {
                ke_hierarchy_component *next = get_hierarchy(impl, h->next_sibling);
                if (next) next->prev_sibling = h->prev_sibling;
            }
        }
    }

    notify_recursive(impl, entity);
    destroy_entities_recursive(impl, entity);
    return KE_OK;
}

static void tree_destroy_all(ke_scene_tree *self)
{
    if (!self || !self->handle) return;
    ke_scene_tree_impl *impl = (ke_scene_tree_impl *)self->handle;
    // Per contract: fire on_destroy hooks only — the world will release the
    // ECS shortly after, so we skip the structural teardown.
    notify_recursive(impl, impl->root);
}

// ── vtable: teardown ──────────────────────────────────────────────────────────

static void tree_destroy(ke_scene_tree *self)
{
    if (!self || !self->handle) return;
    ke_scene_tree_impl *impl = (ke_scene_tree_impl *)self->handle;
    if (impl->allocator) impl->allocator->free(impl->allocator, impl);
}

// ── Factory ───────────────────────────────────────────────────────────────────

ke_result ke_scene_tree_create(struct ke_world *world, ke_allocator *alloc, ke_scene_tree **out_tree)
{
    if (!world || !alloc || !out_tree) return KE_ERROR_INVALID_ARGUMENT;
    ke_ecs_registry *registry = world->get_registry(world);
    if (!registry) return KE_ERROR_NOT_INITIALIZED;
    ke_component_id tcid = world->transform_id(world);
    ke_component_id hcid = world->hierarchy_id(world);
    ke_component_id ncid = world->name_id(world);

    ke_scene_tree_impl *impl = (ke_scene_tree_impl *)alloc->alloc(
        alloc, sizeof(ke_scene_tree_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;
    memset(impl, 0, sizeof(*impl));
    impl->world = world;
    impl->allocator = alloc;
    impl->registry = registry;
    impl->transform_cid = tcid;
    impl->hierarchy_cid = hcid;
    impl->name_cid = ncid;

    // Spin up the root entity with the components the tree relies on. Callers
    // who want a different name on the root can set it after construction —
    // we don't expose a knob here to keep the API surface tight.
    impl->root = ke_ecs_entity_create(registry);
    if (impl->root == KE_ENTITY_INVALID) {
        alloc->free(alloc, impl);
        return KE_ERROR_OUT_OF_MEMORY;
    }
    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_add(
        registry, impl->root, hcid);
    if (!h) {
        ke_ecs_entity_destroy(registry, impl->root);
        alloc->free(alloc, impl);
        return KE_ERROR_OUT_OF_MEMORY;
    }
    h->parent = KE_ENTITY_INVALID;
    h->first_child = KE_ENTITY_INVALID;
    h->next_sibling = KE_ENTITY_INVALID;
    h->prev_sibling = KE_ENTITY_INVALID;

    ke_name_component *n = (ke_name_component *)ke_ecs_component_add(
        registry, impl->root, ncid);
    if (n) {
        strncpy(n->name, "Root", sizeof(n->name) - 1);
        n->name[sizeof(n->name) - 1] = '\0';
    }

    impl->api = (ke_scene_tree){
        .handle       = impl,
        .root         = tree_root,
        .create_node  = tree_create_node,
        .destroy_node = tree_destroy_node,
        .destroy_all  = tree_destroy_all,
        .find_node    = tree_find_node,
        .destroy      = tree_destroy,
    };
    *out_tree = &impl->api;
    return KE_OK;
}
