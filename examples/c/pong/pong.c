#include "pong.h"

#include <kernel_engine/physics/components.h>
#include <kernel_engine/render/ui/components.h>
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

static const ke_component_field pong_paddle_fields[] = {
    { "move_action", KE_VARIANT_STRING, offsetof(pong_paddle, move_action.name), sizeof(((pong_paddle *)0)->move_action.name), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "speed", KE_VARIANT_FLOAT, offsetof(pong_paddle, speed), sizeof(float), { KE_VARIANT_FLOAT, { .f = 7.0 } }, NULL, 0 },
    { "half_height", KE_VARIANT_FLOAT, offsetof(pong_paddle, half_height), sizeof(float), { KE_VARIANT_FLOAT, { .f = 0.9 } }, NULL, 0 },
};

typedef struct pong_ball
{
    char    hit_sound[128];
    char    score_sound[128];
    float   initial_speed;
    ke_vec2 last_velocity;
    bool    awaiting_launch;
    bool    launch_requested;
    int32_t launches;
} pong_ball;

static const ke_component_field pong_ball_fields[] = {
    { "hit_sound", KE_VARIANT_STRING, offsetof(pong_ball, hit_sound), sizeof(((pong_ball *)0)->hit_sound), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "score_sound", KE_VARIANT_STRING, offsetof(pong_ball, score_sound), sizeof(((pong_ball *)0)->score_sound), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "initial_speed", KE_VARIANT_FLOAT, offsetof(pong_ball, initial_speed), sizeof(float), { KE_VARIANT_FLOAT, { .f = 6.0 } }, NULL, 0 },
    { "awaiting_launch", KE_VARIANT_BOOL, offsetof(pong_ball, awaiting_launch), sizeof(bool), { KE_VARIANT_BOOL, { .b = true } }, NULL, 0 },
};

typedef struct pong_scoreboard
{
    int32_t left;
    int32_t right;
} pong_scoreboard;

static const ke_component_field pong_scoreboard_fields[] = {
    { "left", KE_VARIANT_INT, offsetof(pong_scoreboard, left), sizeof(int32_t), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "right", KE_VARIANT_INT, offsetof(pong_scoreboard, right), sizeof(int32_t), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
};

typedef struct pong_goal_scored
{
    bool left_scored;
} pong_goal_scored;

typedef struct pong_ball_launched
{
    bool launched;
} pong_ball_launched;

static const ke_component_params pong_paddle_params = { .name = "pong.paddle", .size = sizeof(pong_paddle), .alignment = _Alignof(pong_paddle), KE_COMPONENT_FIELDS(pong_paddle_fields) };
static const ke_component_params pong_ball_params = { .name = "pong.ball", .size = sizeof(pong_ball), .alignment = _Alignof(pong_ball), KE_COMPONENT_FIELDS(pong_ball_fields) };
static const ke_component_params pong_scoreboard_params = { .name = "pong.scoreboard", .size = sizeof(pong_scoreboard), .alignment = _Alignof(pong_scoreboard), KE_COMPONENT_FIELDS(pong_scoreboard_fields) };
static const ke_component_params pong_goal_scored_params = { .name = "pong.goal_scored", .size = sizeof(pong_goal_scored), .alignment = _Alignof(pong_goal_scored) };
static const ke_component_params pong_ball_launched_params = { .name = "pong.ball_launched", .size = sizeof(pong_ball_launched), .alignment = _Alignof(pong_ball_launched) };

static const char *const pong_body_with[] = { "body2d", "transform2d" };

static ke_label_component *child_label(ke_node_ctx *ctx, pong_game *game, const char *name)
{
    ke_entity child = ctx->child(ctx, ctx->self, name);
    return child == KE_ENTITY_INVALID ? NULL : ctx->component(ctx, child, game->label);
}

static void label_font(ke_node_ctx *ctx, pong_game *game, const char *name)
{
    ke_label_component *label = child_label(ctx, game, name);
    if (label) snprintf(label->font, sizeof label->font, "%s", game->font);
}

static void label_text(ke_node_ctx *ctx, pong_game *game, const char *name, const char *text)
{
    ke_label_component *label = child_label(ctx, game, name);
    if (label) snprintf(label->text, sizeof label->text, "%s", text);
}

static ke_result change_scene(ke_node_ctx *ctx, pong_game *game, const char *path)
{
    ke_result destroyed = ctx->destroy(ctx, game->scene);
    if (destroyed != KE_OK) return destroyed;
    return pong_load_scene(game, ctx->commands, path);
}

static ke_result play(ke_node_ctx *ctx, pong_game *game, const char *sound)
{
    return game->scenes->instantiate(game->scenes, sound, ctx->self, ctx->commands, NULL);
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
    return play(ctx, game, ball->score_sound);
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
            ke_result played = play(ctx, game, ball->hit_sound);
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

static ke_result scoreboard_ready(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    while (ctx->next(ctx))
    {
        label_font(ctx, game, "ScoreLeft");
        label_font(ctx, game, "ScoreRight");
        label_font(ctx, game, "ScoreHint");
        label_text(ctx, game, "ScoreHint", PONG_LAUNCH_HINT);
    }
    return KE_OK;
}

static ke_result scoreboard_on_goal(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_scoreboard, board)
    {
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

static ke_result scoreboard_on_launch(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    while (ctx->next(ctx))
        label_text(ctx, game, "ScoreHint", "");
    return KE_OK;
}

static ke_result menu_ready(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    while (ctx->next(ctx))
    {
        label_font(ctx, game, "Title");
        label_font(ctx, game, "Hint");
    }
    return KE_OK;
}

static ke_result menu_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    while (ctx->next(ctx))
    {
        if (ctx->pressed(ctx, &game->launch)) return change_scene(ctx, game, PONG_MAIN_SCENE);
        if (ctx->pressed(ctx, &game->quit)) game->quit_requested = true;
    }
    return KE_OK;
}

static bool lookup(ke_ecs *ecs, const char *name, ke_component_id *out)
{
    ke_component_meta meta;
    if (!ecs->component_lookup(ecs, name, &meta))
    {
        fprintf(stderr, "pong: component '%s' is not registered\n", name);
        return false;
    }
    *out = meta.cid;
    return true;
}

ke_result pong_load_scene(pong_game *game, ke_ecs_commands *commands, const char *path)
{
    ke_result spawned = game->types->spawn(game->types, commands, game->node, "Scene", KE_ENTITY_INVALID, &game->scene);
    if (spawned != KE_OK) return spawned;
    return game->scenes->instantiate(game->scenes, path, game->scene, commands, NULL);
}

ke_result pong_register(pong_game *game)
{
    ke_node_types *types = game->types;
    ke_result made = types->register_event(types, &pong_goal_scored_params, &game->goal_scored);
    if (made == KE_OK) made = types->register_event(types, &pong_ball_launched_params, &game->ball_launched);
    if (made != KE_OK) return made;

    made = types->find_type(types, "node", &game->node);
    if (made != KE_OK) return made;
    if (!lookup(game->ecs, "label", &game->label) ||
        !lookup(game->ecs, "body2d", &game->body) || !lookup(game->ecs, "transform2d", &game->transform2d))
        return KE_RESULT_NOT_FOUND;
    game->launch = (ke_action_ref){ .name = "Launch" };
    game->quit = (ke_action_ref){ .name = "Quit" };

    const ke_node_handler board_handlers[] = {
        { .event = game->goal_scored, .on = scoreboard_on_goal },
        { .event = game->ball_launched, .on = scoreboard_on_launch },
    };
    const ke_node_type_desc descs[] = {
        { .name = "pong.paddle", .fields = &pong_paddle_params, .with = pong_body_with, .with_count = 2, .fixed_update = paddle_fixed_update, .user_data = game },
        { .name = "pong.ball", .fields = &pong_ball_params, .with = pong_body_with, .with_count = 2, .update = ball_update, .fixed_update = ball_fixed_update, .user_data = game },
        { .name = "pong.scoreboard", .fields = &pong_scoreboard_params, .ready = scoreboard_ready, .on = board_handlers, .on_count = 2, .user_data = game },
        { .name = "pong.menu_controller", .ready = menu_ready, .update = menu_update, .user_data = game },
    };
    for (size_t i = 0; i < sizeof descs / sizeof descs[0]; ++i)
    {
        ke_component_id type = KE_COMPONENT_INVALID;
        ke_result registered = types->register_type(types, &descs[i], &type);
        if (registered != KE_OK) return registered;
    }
    return KE_OK;
}
