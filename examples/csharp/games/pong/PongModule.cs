using KernelEngine.Framework;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Runtime;
using KernelEngine.Ecs;

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
        services.AddNodeType<Wall>("Pong.Wall");
        services.AddNodeType<Paddle>("Pong.Paddle");
        services.AddNodeType<Ball>("Pong.Ball");
        services.AddNodeType<Scoreboard>("Pong.Scoreboard");
        services.AddNodeType<MenuController>("Pong.MenuController");
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var ecs   = services.GetRequiredService<IEcsRegistry>();
        var world = services.GetRequiredService<World>();

        Paddle.RegisterSceneApply(world, ecs);

        Scoreboard.RegisterSceneApply(world, ecs);
    }
}
