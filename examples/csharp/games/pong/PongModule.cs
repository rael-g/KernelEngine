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
