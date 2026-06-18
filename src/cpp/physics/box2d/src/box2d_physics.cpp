#include <box2d/box2d.h>

#include "kernel_engine/physics/box2d/box2d_physics.h"
#include "kernel_engine/common/error.h"
#include "kernel_engine/allocator/allocator.h"
#include "kernel_engine/logger/logger.h"

#include <unordered_map>
#include <cstring>

namespace {

struct Box2dState
{
    ke_allocator                       *allocator;
    ke_logger                          *logger;
    b2World                            *world;
    std::unordered_map<ke_body_2d, b2Body *> bodies;
    ke_body_2d                          next_id;
};

void log_info(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev{ KE_LOG_LEVEL_INFO, "box2d", msg };
    logger->log(logger, &ev);
}

b2Body *lookup(Box2dState *state, ke_body_2d id)
{
    if (id == KE_BODY_2D_INVALID) return nullptr;
    auto it = state->bodies.find(id);
    return (it != state->bodies.end()) ? it->second : nullptr;
}

void physics_destroy(ke_physics_2d *self)
{
    if (!self) return;
    auto *state = static_cast<Box2dState *>(self->handle);
    if (state)
    {
        // b2World destroys all bodies when it goes away — we just delete it.
        delete state->world;
        auto *alloc = state->allocator;
        state->~Box2dState();
        alloc->free(alloc, state);
        alloc->free(alloc, self);
    }
}

void physics_set_gravity(ke_physics_2d *self, float x, float y)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    state->world->SetGravity(b2Vec2(x, y));
}

void physics_step(ke_physics_2d *self, float dt)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    // Box2D recommends fixed velocity/position iteration counts; 8/3 is the documented default.
    state->world->Step(dt, 8, 3);
}

ke_result physics_create_body(ke_physics_2d *self, ke_body_type_2d type, float x, float y, ke_body_2d *out, ke_error **out_error)
{
    if (!out) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    *out = KE_BODY_2D_INVALID;
    auto *state = static_cast<Box2dState *>(self->handle);

    b2BodyDef def;
    def.type = (type == KE_BODY_TYPE_STATIC)    ? b2_staticBody
             : (type == KE_BODY_TYPE_KINEMATIC) ? b2_kinematicBody
                                                : b2_dynamicBody;
    def.position.Set(x, y);

    b2Body *body = state->world->CreateBody(&def);
    if (!body) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "body creation failed");

    if (state->next_id == 0) state->next_id = 1; // skip invalid sentinel
    ke_body_2d id = state->next_id++;
    state->bodies[id] = body;
    *out = id;
    return KE_OK;
}

void physics_destroy_body(ke_physics_2d *self, ke_body_2d id)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    auto it = state->bodies.find(id);
    if (it == state->bodies.end()) return;
    state->world->DestroyBody(it->second);
    state->bodies.erase(it);
}

ke_result physics_add_box(ke_physics_2d *self, ke_body_2d id, float hw, float hh,
                          float density, float friction, float restitution, ke_error **out_error)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    b2Body *body = lookup(state, id);
    if (!body) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "body not found");

    b2PolygonShape shape;
    shape.SetAsBox(hw, hh);

    b2FixtureDef fd;
    fd.shape       = &shape;
    fd.density     = density;
    fd.friction    = friction;
    fd.restitution = restitution;
    body->CreateFixture(&fd);
    return KE_OK;
}

ke_result physics_add_circle(ke_physics_2d *self, ke_body_2d id, float radius,
                             float density, float friction, float restitution, ke_error **out_error)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    b2Body *body = lookup(state, id);
    if (!body) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "body not found");

    b2CircleShape shape;
    shape.m_radius = radius;

    b2FixtureDef fd;
    fd.shape       = &shape;
    fd.density     = density;
    fd.friction    = friction;
    fd.restitution = restitution;
    body->CreateFixture(&fd);
    return KE_OK;
}

void physics_get_state(ke_physics_2d *self, ke_body_2d id, ke_body_state_2d *out)
{
    if (!out) return;
    std::memset(out, 0, sizeof(*out));
    auto *state = static_cast<Box2dState *>(self->handle);
    b2Body *body = lookup(state, id);
    if (!body) return;

    const auto &p = body->GetPosition();
    const auto &v = body->GetLinearVelocity();
    out->x                = p.x;
    out->y                = p.y;
    out->angle            = body->GetAngle();
    out->velocity_x       = v.x;
    out->velocity_y       = v.y;
    out->angular_velocity = body->GetAngularVelocity();
}

void physics_set_position(ke_physics_2d *self, ke_body_2d id, float x, float y, float angle)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    b2Body *body = lookup(state, id);
    if (body) body->SetTransform(b2Vec2(x, y), angle);
}

void physics_set_velocity(ke_physics_2d *self, ke_body_2d id, float vx, float vy)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    b2Body *body = lookup(state, id);
    if (body) body->SetLinearVelocity(b2Vec2(vx, vy));
}

void physics_apply_impulse(ke_physics_2d *self, ke_body_2d id, float ix, float iy)
{
    auto *state = static_cast<Box2dState *>(self->handle);
    b2Body *body = lookup(state, id);
    if (body) body->ApplyLinearImpulseToCenter(b2Vec2(ix, iy), true);
}

} // namespace

extern "C" KE_PHYSICS_BOX2D_API ke_result ke_physics_2d_box2d_create(
    const ke_physics_2d_box2d_params *params, ke_physics_2d_handle *out, ke_error **out_error)
{
    if (!params || !params->allocator || !out) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    auto *alloc = params->allocator;

    auto *state_mem = alloc->alloc(alloc, sizeof(Box2dState), alignof(Box2dState));
    if (!state_mem) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
    auto *state = new (state_mem) Box2dState{};
    state->allocator = alloc;
    state->logger    = params->logger;
    state->next_id   = 1;

    // Use the gravity the caller passed verbatim — zero means zero (top-down games rely on it).
    // C# AddBox2D() defaults to (0, -9.81) so omitting args still gives Earth gravity.
    state->world = new b2World(b2Vec2(params->gravity_x, params->gravity_y));

    auto *api = static_cast<ke_physics_2d *>(alloc->alloc(alloc, sizeof(ke_physics_2d), alignof(ke_physics_2d)));
    if (!api)
    {
        delete state->world;
        state->~Box2dState();
        alloc->free(alloc, state);
        return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "api allocation failed");
    }
    std::memset(api, 0, sizeof(*api));
    api->handle             = state;
    api->set_gravity        = &physics_set_gravity;
    api->step               = &physics_step;
    api->create_body        = &physics_create_body;
    api->destroy_body       = &physics_destroy_body;
    api->add_box_fixture    = &physics_add_box;
    api->add_circle_fixture = &physics_add_circle;
    api->get_body_state     = &physics_get_state;
    api->set_body_position  = &physics_set_position;
    api->set_body_velocity  = &physics_set_velocity;
    api->apply_impulse      = &physics_apply_impulse;

    log_info(state->logger, "Box2D physics world initialized");
    out->ref     = api;
    out->destroy = &physics_destroy;
    return KE_OK;
}
