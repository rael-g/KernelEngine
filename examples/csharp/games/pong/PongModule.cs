using KernelEngine.Framework;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Runtime;
using KernelEngine.Ecs;

namespace Pong;

/// <summary>
/// Wires Pong-specific node types and registers the "paddle" ECS component
/// with its scene-loader apply callback so <c>[entity.components.paddle]</c>
/// in scene files populates <see cref="PaddleComponent"/> correctly.
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

        var paddleCid = ecs.RegisterComponent<PaddleComponent>("paddle");
        world.RegisterComponentApply(paddleCid, static (ref PaddleComponent comp, in VariantReader reader) =>
        {
            if (reader.TryGetString("move_action", out var val) &&
                Enum.TryParse<PongAction>(val, ignoreCase: true, out var action))
            {
                comp.MoveAction = action;
            }
        });

        var scoreboardCid = ecs.RegisterComponent<ScoreboardComponent>("scoreboard");
        world.RegisterComponentApply(scoreboardCid, static (ref ScoreboardComponent comp, in VariantReader reader) =>
        {
            if (reader.TryGetString("font_path", out var path) && !string.IsNullOrEmpty(path))
            {
                var bytes = System.Text.Encoding.UTF8.GetBytes(path!);
                var dst   = (Span<byte>)comp.FontPath;
                var n     = Math.Min(bytes.Length, dst.Length - 1);
                bytes.AsSpan(0, n).CopyTo(dst);
                dst[n] = 0;
            }
            if (reader.TryGetFloat("font_size", out var size) && size > 0f) comp.FontSize = size;
        });
    }
}
