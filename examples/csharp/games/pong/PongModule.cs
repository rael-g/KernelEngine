using KernelEngine.Ecs;
using KernelEngine.Framework;
using KernelEngine.Runtime;

using Microsoft.Extensions.DependencyInjection;

namespace Pong;

/// <summary>
/// Wires Pong-specific node types and the scene-file surface of the components
/// generated for them.
/// </summary>
public sealed class PongModule : IRuntimeModule
{
    public string Name => "Pong";

    public IEnumerable<Type> Dependencies => [typeof(SceneNodesModule)];

    public void Configure(IServiceCollection services)
    {
        services.AddNodeType<Wall>();
        services.AddNodeType<Paddle>();
        services.AddNodeType<Ball>();
        services.AddNodeType<Scoreboard>();
        services.AddNodeType<MenuController>();
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var ecs = services.GetRequiredService<IEcsRegistry>();
        var world = services.GetRequiredService<World>();

        Paddle.RegisterSceneApply(world, ecs);

        Scoreboard.RegisterSceneApply(world, ecs);
    }
}
