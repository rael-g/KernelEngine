using KernelEngine.Framework;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace Pong;

/// <summary>
/// Wires Pong-specific node types and registers the "paddle" ECS component
/// with its scene-loader apply callback so <c>[entity.components.paddle]</c>
/// in scene files populates <see cref="PaddleComponent"/> correctly.
/// </summary>
public sealed class PongModule : IRuntimeModule
{
    public string Name => "Pong";

    public IEnumerable<Type> Dependencies => [typeof(SceneRenderModule)];

    public void Configure(IServiceCollection services)
    {
        services.AddNodeType<Wall>("Pong.Wall");
        services.AddNodeType<Paddle>("Pong.Paddle");
        services.AddNodeType<Ball>("Pong.Ball");
        services.AddNodeType<Scoreboard>("Pong.Scoreboard");
        services.AddNodeType<PhysicsDriver>("Pong.PhysicsDriver");
        services.AddNodeType<MenuController>("Pong.MenuController");
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var ecs   = services.GetRequiredService<IEcsRegistry>();
        var world = services.GetRequiredService<World>();

        var paddleCid = ecs.RegisterComponent<PaddleComponent>("paddle");
        world.RegisterComponentApply(paddleCid, static (ref PaddleComponent comp, in VariantReader reader) =>
        {
            if (reader.TryGetString("move_action", out var val) &&
                Enum.TryParse<PongAction>(val, ignoreCase: true, out var action))
            {
                comp.MoveAction = action;
            }
        });
    }
}
