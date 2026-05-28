using KernelEngine.Configuration;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Physics.Box2D.Native;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace KernelEngine.Physics.Box2D;

/// <summary>
/// POCO bound to <c>[runtime.physics_2d]</c> in the Project file. Defaults to Earth-like downward
/// gravity (matches Box2D's expected MKS units, chapter 24 §7.5).
/// </summary>
public sealed class Box2DOptions
{
    public float GravityX { get; set; } = 0f;
    public float GravityY { get; set; } = -9.81f;
}

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a Box2D-backed <see cref="IPhysics2D"/> singleton. Reads
    /// <c>[runtime.physics_2d]</c> from the Project file when present; otherwise uses
    /// <see cref="Box2DOptions"/> defaults. Requires <c>AddKernel()</c> first.
    /// </summary>
    public static IServiceCollection AddBox2D(this IServiceCollection services)
    {
        services.AddProjectConfigSection<Box2DOptions>("runtime.physics_2d");
        services.AddSingleton<IPhysics2D>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<Box2DOptions>>().Value;
            unsafe
            {
                var logger = sp.GetService<Logger>();
                var @params = new ke_physics_2d_box2d_params
                {
                    allocator = sp.GetRequiredService<Allocator>().Native,
                    logger    = logger != null ? logger.Native : null,
                    gravity_x = opts.GravityX,
                    gravity_y = opts.GravityY,
                };

                ke_physics_2d* native;
                KernelException.ThrowIfFailed(
                    KernelEngine.Physics.Box2D.Native.NativeMethods.physics_2d_box2d_create(&@params, &native).ToManaged());
                return new Physics2D(native);
            }
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes gravity inline. Equivalent to <c>AddBox2D()</c> +
    /// <c>Configure&lt;Box2DOptions&gt;</c>; lets examples that have not migrated to Project keep working.
    /// </summary>
    public static IServiceCollection AddBox2D(
        this IServiceCollection services, float gravityX, float gravityY)
    {
        services.AddBox2D();
        services.Configure<Box2DOptions>(o => { o.GravityX = gravityX; o.GravityY = gravityY; });
        return services;
    }
}
