#ifndef KERNEL_ENGINE_KERNEL_WORLD_SYSTEM_H_
#define KERNEL_ENGINE_KERNEL_WORLD_SYSTEM_H_

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_world;

    /// @brief Interface for a pluggable simulation system.
    /// Register with ke_world::add_system. The world calls update() every frame
    /// and destroy() on world shutdown.
    typedef struct ke_system
    {
        void *handle;
        void (*update)(struct ke_world *world, void *handle, float dt);
        void (*destroy)(void *handle);
    } ke_system;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_SYSTEM_H_
