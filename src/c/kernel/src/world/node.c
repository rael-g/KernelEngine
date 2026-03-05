#include <kernel_engine/kernel/world/node.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

typedef struct ke_node_impl
{
    char name[64];
    ke_transform local_transform;
    ke_mat4 world_matrix;
    bool is_dirty;

    struct ke_node *parent;
    struct ke_node *first_child;
    struct ke_node *next_sibling;
    struct ke_node *prev_sibling;

    ke_entity entity;

    // Callbacks
    ke_result (*on_start)(ke_node *self);
    ke_result (*on_update)(ke_node *self, float dt);
    void *user_data;

    struct ke_allocator *allocator;
    ke_node api;
} ke_node_impl;

static const char *node_get_name(ke_node *self)
{
    return ((ke_node_impl *)self->handle)->name;
}

static ke_result node_get_local_transform(ke_node *self, ke_transform *out_transform)
{
    *out_transform = ((ke_node_impl *)self->handle)->local_transform;
    return KE_OK;
}

static ke_result node_set_local_transform(ke_node *self, const ke_transform *transform)
{
    ke_node_impl *impl = (ke_node_impl *)self->handle;
    impl->local_transform = *transform;
    impl->is_dirty = true;
    return KE_OK;
}

static ke_result node_get_world_matrix(ke_node *self, ke_mat4 *out_matrix)
{
    *out_matrix = ((ke_node_impl *)self->handle)->world_matrix;
    return KE_OK;
}

static ke_result node_add_child(ke_node *self, ke_node *child)
{
    ke_node_impl *impl = (ke_node_impl *)self->handle;
    ke_node_impl *child_impl = (ke_node_impl *)child->handle;

    if (child_impl->parent)
    {
        child_impl->parent->remove_child(child_impl->parent, child);
    }

    child_impl->parent = self;
    child_impl->next_sibling = impl->first_child;
    if (impl->first_child)
    {
        ((ke_node_impl *)impl->first_child->handle)->prev_sibling = child;
    }
    impl->first_child = child;
    child_impl->is_dirty = true;

    return KE_OK;
}

static ke_result node_remove_child(ke_node *self, ke_node *child)
{
    ke_node_impl *impl = (ke_node_impl *)self->handle;
    ke_node_impl *child_impl = (ke_node_impl *)child->handle;

    if (child_impl->parent != self) return KE_ERROR_INVALID_ARGUMENT;

    if (impl->first_child == child)
    {
        impl->first_child = child_impl->next_sibling;
    }

    if (child_impl->next_sibling)
    {
        ((ke_node_impl *)child_impl->next_sibling->handle)->prev_sibling = child_impl->prev_sibling;
    }
    if (child_impl->prev_sibling)
    {
        ((ke_node_impl *)child_impl->prev_sibling->handle)->next_sibling = child_impl->next_sibling;
    }

    child_impl->parent = NULL;
    child_impl->next_sibling = NULL;
    child_impl->prev_sibling = NULL;
    child_impl->is_dirty = true;

    return KE_OK;
}

static ke_node *node_get_parent(ke_node *self) { return ((ke_node_impl *)self->handle)->parent; }
static ke_node *node_get_first_child(ke_node *self) { return ((ke_node_impl *)self->handle)->first_child; }
static ke_node *node_get_next_sibling(ke_node *self) { return ((ke_node_impl *)self->handle)->next_sibling; }

static ke_result node_on_start(ke_node *self)
{
    ke_node_impl *impl = (ke_node_impl *)self->handle;
    if (impl->on_start) return impl->on_start(self);
    return KE_OK;
}

static ke_result node_on_update(ke_node *self, float dt)
{
    ke_node_impl *impl = (ke_node_impl *)self->handle;
    if (impl->on_update) return impl->on_update(self, dt);
    return KE_OK;
}

static ke_entity node_get_entity(ke_node *self) { return ((ke_node_impl *)self->handle)->entity; }
static void node_set_entity(ke_node *self, ke_entity entity) { ((ke_node_impl *)self->handle)->entity = entity; }

static void node_destroy(ke_node *self)
{
    ke_node_impl *impl = (ke_node_impl *)self->handle;
    ke_allocator *alloc = impl->allocator;
    alloc->free(alloc, impl);
}

ke_result ke_node_create(const ke_node_descriptor *desc, ke_node **out_node)
{
    if (!desc || !desc->allocator || !out_node) return KE_ERROR_INVALID_ARGUMENT;

    ke_node_impl *impl = (ke_node_impl *)desc->allocator->alloc(desc->allocator, sizeof(ke_node_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    memset(impl, 0, sizeof(ke_node_impl));
    if (desc->name) strncpy(impl->name, desc->name, 63);
    
    impl->allocator = desc->allocator;
    impl->local_transform.scale.x = 1.0f;
    impl->local_transform.scale.y = 1.0f;
    impl->local_transform.scale.z = 1.0f;
    impl->local_transform.rotation.w = 1.0f;
    impl->is_dirty = true;
    impl->on_start = desc->on_start;
    impl->on_update = desc->on_update;
    impl->user_data = desc->user_data;

    impl->api.handle = impl;
    impl->api.destroy = node_destroy;
    impl->api.get_name = node_get_name;
    impl->api.get_local_transform = node_get_local_transform;
    impl->api.set_local_transform = node_set_local_transform;
    impl->api.get_world_matrix = node_get_world_matrix;
    impl->api.add_child = node_add_child;
    impl->api.remove_child = node_remove_child;
    impl->api.get_parent = node_get_parent;
    impl->api.get_first_child = node_get_first_child;
    impl->api.get_next_sibling = node_get_next_sibling;
    impl->api.on_start = node_on_start;
    impl->api.on_update = node_on_update;
    impl->api.get_entity = node_get_entity;
    impl->api.set_entity = node_set_entity;

    *out_node = &impl->api;
    return KE_OK;
}
