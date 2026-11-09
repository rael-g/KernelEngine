#include "pong.h"

#include <kernel_engine/audio/component_fields.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/physics/component_fields.h>
#include <kernel_engine/physics/components.h>
#include <kernel_engine/render/ui/component_fields.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/sdk/field.h>
#include <kernel_engine/spatial/component_fields.h>
#include <kernel_engine/spatial/transform.h>

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PONG_FIELD_HALF_WIDTH 8.0f
#define PONG_FIELD_HALF_HEIGHT 4.5f
#define PONG_WALL_HALF_THICKNESS 0.25f
#define PONG_GOAL_LINE_MARGIN 0.5f
#define PONG_SERVE_SPREAD 0.6f
#define PONG_MENU_SCENE "res://scenes/Menu.scene.toml"
#define PONG_MAIN_SCENE "res://scenes/Main.scene.toml"
#define PONG_LAUNCH_HINT "Press Space to launch"

typedef struct pong_paddle
{
    ke_action_ref move_action;
    float         speed;
    float         half_height;
} pong_paddle;

static const pong_paddle pong_paddle_initial = { .speed = 7.0f, .half_height = 0.9f };

static const ke_component_field pong_paddle_fields[] = {
    KE_FIELD(pong_paddle, move_action),
    KE_FIELD(pong_paddle, speed),
    KE_FIELD(pong_paddle, half_height),
};

typedef struct pong_ball
{
    char    hit_sound[KE_SOUND_MAX_PATH];
    float   hit_volume;
    char    score_sound[KE_SOUND_MAX_PATH];
    float   score_volume;
    float   initial_speed;
    ke_vec2 last_velocity;
    bool    awaiting_launch;
    bool    launch_requested;
    int32_t launches;
} pong_ball;

static const pong_ball pong_ball_initial = { .hit_volume = 1.0f, .score_volume = 1.0f, .initial_speed = 6.0f, .awaiting_launch = true };

static const ke_component_field pong_ball_fields[] = {
    KE_FIELD(pong_ball, hit_sound),
    KE_FIELD(pong_ball, hit_volume),
    KE_FIELD(pong_ball, score_sound),
    KE_FIELD(pong_ball, score_volume),
    KE_FIELD(pong_ball, initial_speed),
    KE_FIELD(pong_ball, awaiting_launch),
};

typedef struct pong_scoreboard
{
    int32_t left;
    int32_t right;
} pong_scoreboard;

static const ke_component_field pong_scoreboard_fields[] = {
    KE_FIELD(pong_scoreboard, left),
    KE_FIELD(pong_scoreboard, right),
};

typedef struct pong_goal_scored
{
    bool left_scored;
} pong_goal_scored;

typedef struct pong_ball_launched
{
    bool launched;
} pong_ball_launched;

static const ke_component_params pong_paddle_params = KE_COMPONENT(pong_paddle, "pong.paddle", pong_paddle_fields);
static const ke_component_params pong_ball_params = KE_COMPONENT(pong_ball, "pong.ball", pong_ball_fields);
static const ke_component_params pong_scoreboard_params = KE_COMPONENT(pong_scoreboard, "pong.scoreboard", pong_scoreboard_fields);
static const ke_component_params pong_goal_scored_params = KE_COMPONENT_UNTABLED(pong_goal_scored, "pong.goal_scored");
static const ke_component_params pong_ball_launched_params = KE_COMPONENT_UNTABLED(pong_ball_launched, "pong.ball_launched");

static const ke_node_with pong_body_with[] = { { KE_COMPONENT_NAME_BODY2D, &ke_body2d_node_initial, sizeof ke_body2d_node_initial }, { KE_COMPONENT_NAME_TRANSFORM2D, &ke_transform2d_node_initial, sizeof ke_transform2d_node_initial } };

static ke_label_component *child_label(ke_node_ctx *ctx, pong_game *game, const char *name)
{
    ke_entity child = ctx->child(ctx, ctx->self, name);
    return child == KE_ENTITY_INVALID ? NULL : ctx->component(ctx, child, game->label);
}

static void label_text(ke_node_ctx *ctx, pong_game *game, const char *name, const char *text)
{
    ke_label_component *label = child_label(ctx, game, name);
    if (label) snprintf(label->text, sizeof label->text, "%s", text);
}

static ke_result change_scene(ke_node_ctx *ctx, pong_game *game, const char *path)
{
    ke_entity holder = ctx->ancestor(ctx, ctx->self, game->slot);
    ke_scene_slot_component *slot = holder == KE_ENTITY_INVALID ? NULL : ctx->component(ctx, holder, game->slot);
    if (!slot) return KE_RESULT_NOT_FOUND;
    snprintf(slot->path, sizeof slot->path, "%s", path);
    return KE_OK;
}

static ke_result play(ke_node_ctx *ctx, pong_game *game, const char *path, float volume)
{
    ke_sound_component sound = ke_sound_node_initial;
    snprintf(sound.path, sizeof sound.path, "%s", path);
    sound.volume = volume;
    sound.playing = true;
    sound.release = KE_SOUND_RELEASE_WHEN_DONE;
    const ke_node_component components[] = { { game->sound, &sound, sizeof sound } };
    ke_entity node = KE_ENTITY_INVALID;
    return ctx->spawn(ctx, game->sound_type, "Sound", ctx->self, components, 1, &node);
}

static ke_result paddle_fixed_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_paddle, paddle)
    {
        ke_body2d_component *body = ctx->get(ctx, game->body);
        const ke_transform2d_component *pose = ctx->get(ctx, game->transform2d);
        float vy = ctx->axis(ctx, &paddle->move_action) * paddle->speed;
        float max_y = PONG_FIELD_HALF_HEIGHT - PONG_WALL_HALF_THICKNESS - paddle->half_height;
        if (vy > 0 && pose->position.y >= max_y) vy = 0;
        if (vy < 0 && pose->position.y <= -max_y) vy = 0;
        body->velocity = (ke_vec2){ 0.0f, vy };
    }
    return KE_OK;
}

static ke_result ball_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_ball, ball)
    {
        if (ctx->pressed(ctx, &game->quit)) return change_scene(ctx, game, PONG_MENU_SCENE);
        if (ctx->pressed(ctx, &game->launch) && ball->awaiting_launch) ball->launch_requested = true;
    }
    return KE_OK;
}

static ke_result serve(ke_node_ctx *ctx, pong_game *game, pong_ball *ball, ke_body2d_component *body)
{
    ball->awaiting_launch = false;
    ball->launch_requested = false;
    const pong_ball_launched launched = { .launched = true };
    ke_result raised = ctx->raise(ctx, game->ball_launched, &launched, sizeof launched);
    if (raised != KE_OK) return raised;
    float dir_x = ball->launches % 2 == 0 ? 1.0f : -1.0f;
    ball->launches++;
    float dir_y = ((float)rand() / (float)RAND_MAX - 0.5f) * PONG_SERVE_SPREAD;
    float length = sqrtf(dir_x * dir_x + dir_y * dir_y);
    body->velocity = (ke_vec2){ dir_x / length * ball->initial_speed, dir_y / length * ball->initial_speed };
    ball->last_velocity = body->velocity;
    return KE_OK;
}

static ke_result score(ke_node_ctx *ctx, pong_game *game, pong_ball *ball, ke_body2d_component *body, ke_transform2d_component *pose, bool left_scored)
{
    const pong_goal_scored goal = { .left_scored = left_scored };
    ke_result raised = ctx->raise(ctx, game->goal_scored, &goal, sizeof goal);
    if (raised != KE_OK) return raised;
    pose->position = (ke_vec2){ 0.0f, 0.0f };
    body->velocity = (ke_vec2){ 0.0f, 0.0f };
    ball->last_velocity = (ke_vec2){ 0.0f, 0.0f };
    ball->awaiting_launch = true;
    return play(ctx, game, ball->score_sound, ball->score_volume);
}

static ke_result ball_fixed_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_ball, ball)
    {
        ke_body2d_component *body = ctx->get(ctx, game->body);
        ke_transform2d_component *pose = ctx->get(ctx, game->transform2d);
        if (ball->launch_requested)
        {
            ke_result served = serve(ctx, game, ball, body);
            if (served != KE_OK) return served;
        }
        if (ball->awaiting_launch) continue;

        bool bounced = ball->last_velocity.x != 0 && (body->velocity.x > 0) != (ball->last_velocity.x > 0);
        ball->last_velocity = body->velocity;
        if (bounced)
        {
            ke_result played = play(ctx, game, ball->hit_sound, ball->hit_volume);
            if (played != KE_OK) return played;
        }

        bool left_scored = pose->position.x > PONG_FIELD_HALF_WIDTH + PONG_GOAL_LINE_MARGIN;
        if (left_scored || pose->position.x < -PONG_FIELD_HALF_WIDTH - PONG_GOAL_LINE_MARGIN)
        {
            ke_result scored = score(ctx, game, ball, body, pose, left_scored);
            if (scored != KE_OK) return scored;
        }
    }
    return KE_OK;
}

static ke_result scoreboard_on(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_scoreboard, board)
    {
        if (ctx->event_type == game->ball_launched)
        {
            label_text(ctx, game, "ScoreHint", "");
            continue;
        }
        const pong_goal_scored *goal = ctx->event;
        if (goal->left_scored) board->left++;
        else board->right++;
        char digits[16];
        snprintf(digits, sizeof digits, "%d", board->left);
        label_text(ctx, game, "ScoreLeft", digits);
        snprintf(digits, sizeof digits, "%d", board->right);
        label_text(ctx, game, "ScoreRight", digits);
        label_text(ctx, game, "ScoreHint", PONG_LAUNCH_HINT);
    }
    return KE_OK;
}

static ke_result menu_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    while (ctx->next(ctx))
    {
        if (ctx->pressed(ctx, &game->launch)) return change_scene(ctx, game, PONG_MAIN_SCENE);
        if (ctx->pressed(ctx, &game->quit)) ctx->exit(ctx);
    }
    return KE_OK;
}

ke_result pong_open_slot(pong_game *game, ke_ecs_commands *commands, const char *path)
{
    ke_scene_slot_component slot = { 0 };
    snprintf(slot.path, sizeof slot.path, "%s", path);
    const ke_node_component components[] = { { game->slot, &slot, sizeof slot } };
    ke_entity node = KE_ENTITY_INVALID;
    return game->types->spawn(game->types, commands, game->slot_type, "Scene", KE_ENTITY_INVALID, components, 1, &node);
}

ke_result pong_register(pong_game *game)
{
    ke_node_types *types = game->types;
    ke_result made = types->register_event(types, &pong_goal_scored_params, &game->goal_scored);
    if (made == KE_OK) made = types->register_event(types, &pong_ball_launched_params, &game->ball_launched);
    if (made != KE_OK) return made;

    made = types->find_type(types, KE_COMPONENT_NAME_SCENE_SLOT, &game->slot_type);
    if (made == KE_OK) made = types->find_component(types, KE_COMPONENT_NAME_SCENE_SLOT, &game->slot);
    if (made == KE_OK) made = types->find_type(types, "sound", &game->sound_type);
    if (made == KE_OK) made = types->find_component(types, KE_COMPONENT_NAME_SOUND, &game->sound);
    if (made != KE_OK) return made;
    if (made == KE_OK) made = types->find_component(types, KE_COMPONENT_NAME_LABEL, &game->label);
    if (made == KE_OK) made = types->find_component(types, KE_COMPONENT_NAME_BODY2D, &game->body);
    if (made == KE_OK) made = types->find_component(types, KE_COMPONENT_NAME_TRANSFORM2D, &game->transform2d);
    if (made != KE_OK) return made;
    game->launch = (ke_action_ref){ .name = "Launch" };
    game->quit = (ke_action_ref){ .name = "Quit" };

    const ke_component_id board_events[] = { game->goal_scored, game->ball_launched };
    const ke_node_type_desc descs[] = {
        { .name = "pong.paddle", .fields = &pong_paddle_params, .initial = &pong_paddle_initial, .initial_size = sizeof pong_paddle_initial, .with = pong_body_with, .with_count = 2, .fixed_update = paddle_fixed_update, .user_data = game },
        { .name = "pong.ball", .fields = &pong_ball_params, .initial = &pong_ball_initial, .initial_size = sizeof pong_ball_initial, .with = pong_body_with, .with_count = 2, .update = ball_update, .fixed_update = ball_fixed_update, .user_data = game },
        { .name = "pong.scoreboard", .fields = &pong_scoreboard_params, .events = board_events, .event_count = 2, .on = scoreboard_on, .user_data = game },
        { .name = "pong.menu_controller", .update = menu_update, .user_data = game },
    };
    for (size_t i = 0; i < sizeof descs / sizeof descs[0]; ++i)
    {
        ke_component_id type = KE_COMPONENT_INVALID;
        ke_result registered = types->register_type(types, &descs[i], &type);
        if (registered != KE_OK) return registered;
    }
    return KE_OK;
}
