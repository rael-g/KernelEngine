using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Physics.Native;
using KernelEngine.Runtime;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Physics;

/// <summary>
/// Registers the native system that turns a <c>Body2D</c> node into a simulated body:
/// it creates the body at the node's transform, steps the world, and writes the pose
/// back into the transform and the motion into the component. Without this module a
/// <c>Body2D</c> is storage that nothing advances. It requires a
/// <see cref="KernelEngine.Framework.World"/>, whose scene tree tells it when a collider's
/// ancestors may have changed.
/// </summary>
public sealed unsafe class Body2DModule : IRuntimeModule
{
    private ke_physics_body2d_module_handle _handle;

    /// <summary>
    /// Registers this domain's node types so a scene naming them resolves.
    /// </summary>
    public void Configure(IServiceCollection services)
    {
        KernelEngine.Framework.PhysicsComponentsNodeTypes.AddPhysicsComponentsNodeTypes(services);
    }

    /// <inheritdoc />
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var ecs = services.GetRequiredService<INativeEcs>();
        var physics = services.GetRequiredService<IPhysics2D>();

        var logger = services.GetService<KernelEngine.Logger.INativeLogger>();
        var world = services.GetRequiredService<KernelEngine.Framework.World>();

        var @params = new ke_physics_body2d_module_params
        {
            runtime = ((INativeRuntime)runtime).Native,
            ecs = ((INativeEcs)ecs).Native,
            physics = ((INativePhysics2d)physics).Native,
            scene_tree = ((KernelEngine.Framework.INativeSceneTree)world.SceneTree).Native,
            logger = logger is not null ? logger.Native : null,
        };

        ke_error* err = null;
        _handle = KernelEngine.Physics.Native.NativeMethods.physics_body2d_module_create(&@params, &err);
        if (_handle.@ref == null) throw NativeErrors.FromNative(err, "physics_body2d_module_create");

        var set = KernelEngine.Physics.Native.NativeMethods.physics_scene_components_create();
        try
        {
            err = null;
            if (!set.@ref->register_into(set.@ref, ((INativeEcs)ecs).Native,
                    ((KernelEngine.Framework.INativeWorld)world).Native, &err))
                throw NativeErrors.FromNative(err, "register_into");
        }
        finally
        {
            set.destroy(set.@ref);
        }
    }

    /// <inheritdoc />
    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_handle.@ref == null) return;
        _handle.destroy(_handle.@ref);
        _handle.@ref = null;
    }
}

/// <summary>DI helpers for the 2D body simulation module.</summary>
public static class Body2DServiceCollectionExtensions
{
    /// <summary>
    /// Adds the system that simulates <c>Body2D</c> nodes. Requires an
    /// <see cref="IPhysics2D"/> backend to already be registered.
    /// </summary>
    public static IServiceCollection AddBody2D(this IServiceCollection services)
        => services.Add<IRuntimeModule>(new Body2DModule());
}
