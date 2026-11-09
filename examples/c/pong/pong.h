#ifndef PONG_PONG_H_
#define PONG_PONG_H_

#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/framework/scene_files.h>

#include <stdbool.h>

/** What Pong's node types are given: the engine parts they call and the ids they look up once. */
typedef struct pong_game
{
    ke_node_types    *types;
    ke_scene_files   *scenes;
    ke_component_id node;
    ke_component_id label;
    ke_component_id body;
    ke_component_id transform2d;
    ke_component_id goal_scored;
    ke_component_id ball_launched;
    ke_action_ref   launch;
    ke_action_ref   quit;

    /** The node the current scene is instantiated under. */
    ke_entity scene;
} pong_game;

/**
 * Registers Pong's events and node types and looks up the ids @p game keeps.
 * @param game The engine parts filled in; the ids and the scene are written.
 * @return KE_OK, or the code of the registration or lookup that failed.
 */
ke_result pong_register(pong_game *game);

/**
 * Records into @p commands a node named Scene at the root and the scene file @p path under it.
 * @param path [utf8]
 * @return KE_OK, or the code of the spawn or the instantiation that failed.
 */
ke_result pong_load_scene(pong_game *game, ke_ecs_commands *commands, const char *path);

#endif
