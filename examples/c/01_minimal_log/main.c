#include <kernel_engine/physics/box2d/box2d_physics.h>
#include <kernel_engine/physics/box2d/physics_2d_box2d_log.h>
#include <stdio.h>

static const char *level_name(ke_log_level level)
{
    switch (level)
    {
    case KE_LOG_LEVEL_ERROR:   return "ERROR";
    case KE_LOG_LEVEL_WARNING: return "WARNING";
    case KE_LOG_LEVEL_INFO:    return "INFO";
    default:                   return "DEBUG";
    }
}

static void print_line(void *ctx, ke_log_level level, const char *scope, const char *message)
{
    (void)ctx;
    printf("[%s] %s: %s\n", level_name(level), scope, message);
}

int main(void)
{
    printf("--- KernelEngine C Minimal Log Demo ---\n");

    ke_physics_2d_box2d_set_log_callback(print_line, NULL);

    ke_physics_2d_box2d_params params = {.gravity_x = 0.0f, .gravity_y = -9.81f};
    ke_physics_2d_handle physics = {0};
    if (ke_physics_2d_box2d_create(&params, &physics) == KE_OK)
        physics.destroy(physics.ref);

    printf("--- Demo Complete ---\n");
    return 0;
}
