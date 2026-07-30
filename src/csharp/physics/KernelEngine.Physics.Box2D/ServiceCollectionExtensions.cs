using KernelEngine.Configuration;
using KernelEngine.Common.Native;
using KernelEngine.Physics.Box2D.Native;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Logger;

namespace KernelEngine.Physics.Box2D;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a Box2D-backed <see cref="IPhysics2D"/> singleton. Reads
    /// <c>[runtime.physics_2d] gravity_x/gravity_y</c> from the Project file when present;
    /// otherwise defaults to Earth-like downward gravity (matches Box2D's expected MKS units).
    /// </summary>
    public static IServiceCollection AddBox2D(this IServiceCollection services)
    {
        services.TryAddConfigurationSingleton();
        services.AddSingleton<IPhysics2D>(sp =>
        {
            var cfg = sp.GetRequiredService<IConfiguration>();
            var gravityX = (float)cfg.GetDouble("runtime.physics_2d", "gravity_x", 0.0);
            var gravityY = (float)cfg.GetDouble("runtime.physics_2d", "gravity_y", -9.81);
            return CreatePhysics(sp, gravityX, gravityY);
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes gravity inline, bypassing the Project file.
    /// Lets examples that have not migrated to Project keep working.
    /// </summary>
    public static IServiceCollection AddBox2D(
        this IServiceCollection services, float gravityX, float gravityY)
    {
        services.AddSingleton<IPhysics2D>(sp => CreatePhysics(sp, gravityX, gravityY));
        return services;
    }

    private static unsafe IPhysics2D CreatePhysics(IServiceProvider sp, float gravityX, float gravityY)
    {
        var logger = sp.GetService<INativeLogger>();
        var @params = new ke_physics_2d_box2d_params
        {
            logger    = logger != null ? logger.Native : null,
            gravity_x = gravityX,
            gravity_y = gravityY,
        };

        ke_error* err = null;
        var handle = KernelEngine.Physics.Box2D.Native.NativeMethods.physics_2d_box2d_create(&@params, &err);
        if (handle.@ref == null) throw KernelError.FromNative(err, "physics_2d_box2d_create");
        return new Physics2D(handle);
    }
}
