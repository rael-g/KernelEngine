#include <kernel_engine/kernel/world/scene.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

typedef struct ke_scene_impl
{
    struct ke_node *root;
    struct ke_allocator *allocator;
    ke_scene api;
} ke_scene_impl;

static struct ke_node *scene_get_root(ke_scene *self)
{
    return ((ke_scene_impl *)self->handle)->root;
}

static ke_result scene_create_node(ke_scene *self, const ke_node_descriptor *desc, ke_node **out_node)
{
    ke_scene_impl *impl = (ke_scene_impl *)self->handle;
    ke_node_descriptor full_desc = *desc;
    full_desc.allocator = impl->allocator;
    return ke_node_create(&full_desc, out_node);
}

static void scene_destroy_node_recursive(ke_node *node)
{
    if (!node) return;
    ke_node *child = node->get_first_child(node);
    while (child)
    {
        ke_node *next = child->get_next_sibling(child);
        scene_destroy_node_recursive(child);
        child = next;
    }
    node->destroy(node);
}

static ke_result scene_destroy_node(ke_scene *self, ke_node *node)
{
    ke_scene_impl *impl = (ke_scene_impl *)self->handle;
    if (node == impl->root) return KE_ERROR_INVALID_ARGUMENT;

    ke_node *parent = node->get_parent(node);
    if (parent) parent->remove_child(parent, node);

    scene_destroy_node_recursive(node);
    return KE_OK;
}

static void node_update_recursive(ke_node *node, const ke_mat4 *parent_world)
{
    if (!node) return;

    // Use internal cast to access dirty flag if needed, 
    // but for now, we'll follow the public API.
    ke_mat4 world;
    ke_transform local;
    node->get_local_transform(node, &local);
    
    ke_mat4 local_mat;
    ke_mat4_from_transform(&local_mat, &local.position, &local.rotation, &local.scale);

    if (parent_world)
    {
        ke_mat4_mul(&world, parent_world, &local_mat);
    }
    else
    {
        memcpy(&world, &local_mat, sizeof(ke_mat4));
    }

    node->set_world_matrix(node, &world);

    ke_node *child = node->get_first_child(node);
    while (child)
    {
        node_update_recursive(child, &world);
        child = child->get_next_sibling(child);
    }
}

static void scene_update(ke_scene *self)
{
    ke_scene_impl *impl = (ke_scene_impl *)self->handle;
    node_update_recursive(impl->root, NULL);
}

static void scene_destroy(ke_scene *self)
{
    ke_scene_impl *impl = (ke_scene_impl *)self->handle;
    scene_destroy_node_recursive(impl->root);
    impl->allocator->free(impl->allocator, impl);
}

ke_result ke_scene_create(const ke_scene_descriptor *desc, ke_scene **out_scene)
{
    if (!desc || !desc->allocator || !out_scene) return KE_ERROR_INVALID_ARGUMENT;

    ke_scene_impl *impl = (ke_scene_impl *)desc->allocator->alloc(desc->allocator, sizeof(ke_scene_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    impl->allocator = desc->allocator;
    
    ke_node_descriptor root_desc = { .name = "Root", .allocator = impl->allocator };
    ke_node_create(&root_desc, &impl->root);

    impl->api.handle = impl;
    impl->api.destroy = scene_destroy;
    impl->api.get_root = scene_get_root;
    impl->api.create_node = scene_create_node;
    impl->api.destroy_node = scene_destroy_node;
    impl->api.update = scene_update;

    *out_scene = &impl->api;
    return KE_OK;
}
