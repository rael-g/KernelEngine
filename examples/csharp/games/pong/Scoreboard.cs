using KernelEngine.Framework.Nodes;
using KernelEngine.Render;

namespace Pong;

/// <summary>The scoreboard: shows the score, and the hint to serve between goals.</summary>
[NodeType("pong.scoreboard")]
partial class Scoreboard : Node
{
    const string LaunchHint = "Press Space to launch";

    [On<ScoreChanged>]
    void OnScore(ScoreChanged score)
    {
        Show("ScoreLeft", score.Left.ToString());
        Show("ScoreRight", score.Right.ToString());
        Show("ScoreHint", LaunchHint);
    }

    [On<ServeRequested>]
    void OnServe(ServeRequested _) => Show("ScoreHint", "");

    void Show(string child, string text) => Get<LabelComponent>(Child(child)).Text = text;
}
