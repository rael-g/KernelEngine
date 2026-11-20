#ifndef PONG_PONG_H_
#define PONG_PONG_H_

#include <kernel_engine/framework/node_types.h>

#include <stdbool.h>
#include <stdint.h>

/** The event a match raises when a side scores: the score after the goal. */
typedef struct pong_score_changed
{
    int32_t left;
    int32_t right;
} pong_score_changed;

/** What Pong's node types are given: the node types they register into and the ids of their events. */
typedef struct pong_game
{
    ke_node_types  *types;
    ke_component_id goal_scored;
    ke_component_id serve_requested;
    ke_component_id score_changed;
} pong_game;

/**
 * Registers Pong's events and node types and keeps the events' ids.
 * @param game The engine parts filled in; the ids are written.
 * @return KE_OK, or the code of the registration or lookup that failed.
 */
ke_result pong_register(pong_game *game);

#endif
