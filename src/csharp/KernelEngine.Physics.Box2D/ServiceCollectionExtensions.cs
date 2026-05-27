using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Physics.Box2D.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Physics.Box2D;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a Box2D-backed <see cref="IPhysics2D"/> singleton with the given gravity
    /// (default: 0, -9.81 m/s²). Requires <c>AddKernel()</c> to be called first.
    /// </summary>
    public static IServiceCollection AddBox2D(
        this IServiceCollection services, float gravityX = 0f, float gravityY = -9.81f)
    {
        services.AddSingleton<IPhysics2D>(sp =>
        {
            unsafe
            {
                var logger = sp.GetService<Logger>();
                var @params = new ke_physics_2d_box2d_params
                {
                    allocator = sp.GetRequiredService<Allocator>().Native,
                    logger    = logger != null ? logger.Native : null,
                    gravity_x = gravityX,
                    gravity_y = gravityY,
                };

                ke_physics_2d* native;
                KernelException.ThrowIfFailed(
                    KernelEngine.Physics.Box2D.Native.NativeMethods.physics_2d_box2d_create(&@params, &native).ToManaged());
                return new Physics2D(native);
            }
        });
        return services;
    }
}
