#include "pong.h"

#include <kernel_engine/audio/component_fields.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/physics/component_fields.h>
#include <kernel_engine/render/ui/component_fields.h>
#include <kernel_engine/sdk/field.h>
#include <kernel_engine/sdk/node.h>
#include <kernel_engine/spatial/component_fields.h>

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#define PONG_FIELD_HALF_WIDTH 8.0f
#define PONG_FIELD_HALF_HEIGHT 4.5f
#define PONG_WALL_HALF_THICKNESS 0.25f
#define PONG_GOAL_LINE_MARGIN 0.5f
#define PONG_SERVE_SPREAD 0.6f
#define PONG_MENU_SCENE "res://scenes/Menu.scene.toml"
#define PONG_MAIN_SCENE "res://scenes/Main.scene.toml"
#define PONG_LAUNCH_HINT "Press Space to launch"

typedef struct pong_match
{
    char    score_sound[KE_SOUND_MAX_PATH];
    float   score_volume;
    int32_t left;
    int32_t right;
    bool    serving;
} pong_match;

static const pong_match pong_match_initial = { .score_volume = 1.0f, .serving = true };

static const ke_component_field pong_match_fields[] = {
    KE_FIELD(pong_match, score_sound),
    KE_FIELD(pong_match, score_volume),
};

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
    float   initial_speed;
    ke_vec2 last_velocity;
    int32_t serves;
} pong_ball;

static const pong_ball pong_ball_initial = { .hit_volume = 1.0f, .initial_speed = 6.0f };

static const ke_component_field pong_ball_fields[] = {
    KE_FIELD(pong_ball, hit_sound),
    KE_FIELD(pong_ball, hit_volume),
    KE_FIELD(pong_ball, initial_speed),
};

typedef struct pong_goal_scored
{
    bool left_scored;
} pong_goal_scored;

typedef struct pong_serve_requested
{
    bool requested;
} pong_serve_requested;

typedef struct pong_score_changed
{
    int32_t left;
    int32_t right;
} pong_score_changed;

static const ke_component_params pong_goal_scored_params = KE_COMPONENT_UNTABLED(pong_goal_scored, "pong.goal_scored");
static const ke_component_params pong_serve_requested_params = KE_COMPONENT_UNTABLED(pong_serve_requested, "pong.serve_requested");
static const ke_component_params pong_score_changed_params = KE_COMPONENT_UNTABLED(pong_score_changed, "pong.score_changed");

static ke_result play(ke_node_ctx *ctx, const char *path, float volume)
{
    ke_sound_component sound = ke_sound_node_initial;
    snprintf(sound.path, sizeof sound.path, "%s", path);
    sound.volume = volume;
    sound.playing = true;
    sound.release = KE_SOUND_RELEASE_WHEN_DONE;
    return ke_sdk_spawn(ctx, KE_COMPONENT_NAME_SOUND, "Sound", &sound, sizeof sound);
}

static void show(ke_node_ctx *ctx, const char *child, const char *text)
{
    ke_label_component *label = ke_sdk_get(ctx, ctx->child(ctx, ctx->self, child), KE_COMPONENT_NAME_LABEL);
    if (label) snprintf(label->text, sizeof label->text, "%s", text);
}

static ke_result match_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_match, match)
    {
        if (ctx->pressed_named(ctx, "Quit")) return ctx->change_scene(ctx, PONG_MENU_SCENE);
        if (match->serving && ctx->pressed_named(ctx, "Launch"))
        {
            match->serving = false;
            const pong_serve_requested serve = { .requested = true };
            ke_result raised = ctx->raise(ctx, game->serve_requested, &serve, sizeof serve);
            if (raised != KE_OK) return raised;
        }
    }
    return KE_OK;
}

static ke_result match_on(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_match, match)
    {
        const pong_goal_scored *goal = ctx->event;
        if (goal->left_scored) match->left++;
        else match->right++;
        match->serving = true;
        const pong_score_changed score = { .left = match->left, .right = match->right };
        ke_result raised = ctx->raise(ctx, game->score_changed, &score, sizeof score);
        if (raised == KE_OK) raised = play(ctx, match->score_sound, match->score_volume);
        if (raised != KE_OK) return raised;
    }
    return KE_OK;
}

static ke_result paddle_fixed_update(ke_node_ctx *ctx, void *user_data)
{
    (void)user_data;
    KE_FOR_EACH_NODE(ctx, pong_paddle, paddle)
    {
        ke_body2d_component *body = ke_sdk_get(ctx, ctx->self, KE_COMPONENT_NAME_BODY2D);
        const ke_transform2d_component *pose = ke_sdk_get(ctx, ctx->self, KE_COMPONENT_NAME_TRANSFORM2D);
        float vy = ctx->axis(ctx, &paddle->move_action) * paddle->speed;
        float max_y = PONG_FIELD_HALF_HEIGHT - PONG_WALL_HALF_THICKNESS - paddle->half_height;
        if (vy > 0 && pose->position.y >= max_y) vy = 0;
        if (vy < 0 && pose->position.y <= -max_y) vy = 0;
        body->velocity = (ke_vec2){ 0.0f, vy };
    }
    return KE_OK;
}

static ke_result ball_on(ke_node_ctx *ctx, void *user_data)
{
    (void)user_data;
    KE_FOR_EACH_NODE(ctx, pong_ball, ball)
    {
        ke_body2d_component *body = ke_sdk_get(ctx, ctx->self, KE_COMPONENT_NAME_BODY2D);
        float dir_x = ball->serves % 2 == 0 ? 1.0f : -1.0f;
        ball->serves++;
        float dir_y = ((float)rand() / (float)RAND_MAX - 0.5f) * PONG_SERVE_SPREAD;
        float length = sqrtf(dir_x * dir_x + dir_y * dir_y);
        body->velocity = (ke_vec2){ dir_x / length * ball->initial_speed, dir_y / length * ball->initial_speed };
        ball->last_velocity = body->velocity;
    }
    return KE_OK;
}

static ke_result ball_fixed_update(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    KE_FOR_EACH_NODE(ctx, pong_ball, ball)
    {
        ke_body2d_component *body = ke_sdk_get(ctx, ctx->self, KE_COMPONENT_NAME_BODY2D);
        ke_transform2d_component *pose = ke_sdk_get(ctx, ctx->self, KE_COMPONENT_NAME_TRANSFORM2D);
        bool bounced = ball->last_velocity.x != 0 && (body->velocity.x > 0) != (ball->last_velocity.x > 0);
        ball->last_velocity = body->velocity;
        if (bounced)
        {
            ke_result played = play(ctx, ball->hit_sound, ball->hit_volume);
            if (played != KE_OK) return played;
        }

        bool left_scored = pose->position.x > PONG_FIELD_HALF_WIDTH + PONG_GOAL_LINE_MARGIN;
        if (!left_scored && pose->position.x >= -PONG_FIELD_HALF_WIDTH - PONG_GOAL_LINE_MARGIN) continue;
        pose->position = (ke_vec2){ 0.0f, 0.0f };
        body->velocity = (ke_vec2){ 0.0f, 0.0f };
        ball->last_velocity = (ke_vec2){ 0.0f, 0.0f };
        const pong_goal_scored goal = { .left_scored = left_scored };
        ke_result raised = ctx->raise(ctx, game->goal_scored, &goal, sizeof goal);
        if (raised != KE_OK) return raised;
    }
    return KE_OK;
}

static ke_result scoreboard_on(ke_node_ctx *ctx, void *user_data)
{
    pong_game *game = user_data;
    while (ctx->next(ctx))
    {
        if (ctx->event_type == game->serve_requested)
        {
            show(ctx, "ScoreHint", "");
            continue;
        }
        const pong_score_changed *score = ctx->event;
        char digits[16];
        snprintf(digits, sizeof digits, "%d", score->left);
        show(ctx, "ScoreLeft", digits);
        snprintf(digits, sizeof digits, "%d", score->right);
        show(ctx, "ScoreRight", digits);
        show(ctx, "ScoreHint", PONG_LAUNCH_HINT);
    }
    return KE_OK;
}

static ke_result menu_update(ke_node_ctx *ctx, void *user_data)
{
    (void)user_data;
    while (ctx->next(ctx))
    {
        if (ctx->pressed_named(ctx, "Launch")) return ctx->change_scene(ctx, PONG_MAIN_SCENE);
        if (ctx->pressed_named(ctx, "Quit")) ctx->exit(ctx);
    }
    return KE_OK;
}

ke_result pong_register(pong_game *game)
{
    ke_node_types *types = game->types;
    ke_result made = types->register_event(types, &pong_goal_scored_params, &game->goal_scored);
    if (made == KE_OK) made = types->register_event(types, &pong_serve_requested_params, &game->serve_requested);
    if (made == KE_OK) made = types->register_event(types, &pong_score_changed_params, &game->score_changed);
    if (made != KE_OK) return made;

    const ke_component_id match_events[] = { game->goal_scored };
    const ke_component_id ball_events[] = { game->serve_requested };
    const ke_component_id board_events[] = { game->score_changed, game->serve_requested };
    const ke_node_type_desc descs[] = {
        { .name = "pong.match", KE_NODE_FIELDS(pong_match, pong_match_fields), .initial = &pong_match_initial, .initial_size = sizeof pong_match_initial, .update = match_update, .events = match_events, .event_count = 1, .on = match_on, .user_data = game },
        { .name = "pong.paddle", KE_NODE_FIELDS(pong_paddle, pong_paddle_fields), .initial = &pong_paddle_initial, .initial_size = sizeof pong_paddle_initial, KE_NODE_EXTENDS(ke_body2d_node_with), .fixed_update = paddle_fixed_update, .user_data = game },
        { .name = "pong.ball", KE_NODE_FIELDS(pong_ball, pong_ball_fields), .initial = &pong_ball_initial, .initial_size = sizeof pong_ball_initial, KE_NODE_EXTENDS(ke_body2d_node_with), .fixed_update = ball_fixed_update, .events = ball_events, .event_count = 1, .on = ball_on, .user_data = game },
        { .name = "pong.scoreboard", .events = board_events, .event_count = 2, .on = scoreboard_on, .user_data = game },
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
