#ifndef KERNEL_ENGINE_SDK_NODE_H_
#define KERNEL_ENGINE_SDK_NODE_H_

#include <kernel_engine/audio/component_fields.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/framework/scene_files.h>

#include <stdio.h>

/**
 * @file
 * What a node of a C game does in one call that the node context does in several: open or change a
 * scene, play a sound.
 */

/** The engine ids the calls of this file use, found once from the node types. */
typedef struct ke_sdk_nodes
{
    /** The scene slot node type. */
    ke_component_id slot_type;
    /** The scene slot component. */
    ke_component_id slot;
    /** The sound node type. */
    ke_component_id sound_type;
    /** The sound component. */
    ke_component_id sound;
} ke_sdk_nodes;

/**
 * Finds the engine ids into @p out.
 * @param types The node types, the engine's registered and the scene files created.
 * @return KE_OK, or the code of the lookup that failed.
 */
static inline ke_result ke_sdk_nodes_find(ke_node_types *types, ke_sdk_nodes *out)
{
    ke_result found = types->find_type(types, KE_COMPONENT_NAME_SCENE_SLOT, &out->slot_type);
    if (found == KE_OK) found = types->find_component(types, KE_COMPONENT_NAME_SCENE_SLOT, &out->slot);
    if (found == KE_OK) found = types->find_type(types, KE_COMPONENT_NAME_SOUND, &out->sound_type);
    if (found == KE_OK) found = types->find_component(types, KE_COMPONENT_NAME_SOUND, &out->sound);
    return found;
}

/**
 * Records into @p commands a scene slot at the root holding the scene file at @p path.
 * @param path [utf8]
 * @return KE_OK, or the code of the spawn that failed.
 */
static inline ke_result ke_sdk_open_scene(ke_node_types *types, const ke_sdk_nodes *nodes, ke_ecs_commands *commands, const char *path)
{
    ke_scene_slot_component slot = { 0 };
    snprintf(slot.path, sizeof slot.path, "%s", path);
    const ke_node_component components[] = { { nodes->slot, &slot, sizeof slot } };
    ke_entity node = KE_ENTITY_INVALID;
    return types->spawn(types, commands, nodes->slot_type, "Scene", KE_ENTITY_INVALID, components, 1, &node);
}

/**
 * Points the scene slot holding the current node at the scene file at @p path.
 * @param path [utf8]
 * @return KE_OK; KE_RESULT_NOT_FOUND when no scene slot holds the node.
 */
static inline ke_result ke_sdk_change_scene(ke_node_ctx *ctx, const ke_sdk_nodes *nodes, const char *path)
{
    ke_entity holder = ctx->ancestor(ctx, ctx->self, nodes->slot);
    ke_scene_slot_component *slot = holder == KE_ENTITY_INVALID ? NULL : ctx->component(ctx, holder, nodes->slot);
    if (!slot) return KE_RESULT_NOT_FOUND;
    snprintf(slot->path, sizeof slot->path, "%s", path);
    return KE_OK;
}

/**
 * Plays the sound file at @p path once at @p volume, as a sound node under the current node that
 * is destroyed when the sound ends.
 * @param path [utf8]
 * @return KE_OK, or the code of the spawn that failed.
 */
static inline ke_result ke_sdk_play_sound(ke_node_ctx *ctx, const ke_sdk_nodes *nodes, const char *path, float volume)
{
    ke_sound_component sound = ke_sound_node_initial;
    snprintf(sound.path, sizeof sound.path, "%s", path);
    sound.volume = volume;
    sound.playing = true;
    sound.release = KE_SOUND_RELEASE_WHEN_DONE;
    const ke_node_component components[] = { { nodes->sound, &sound, sizeof sound } };
    ke_entity node = KE_ENTITY_INVALID;
    return ctx->spawn(ctx, nodes->sound_type, "Sound", ctx->self, components, 1, &node);
}

#endif
