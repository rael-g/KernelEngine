using KernelEngine.Framework.Nodes;
using KernelEngine.Render;

namespace Pong;

/// <summary>The scoreboard: counts goals and shows the hint to serve between them.</summary>
[NodeType("pong.scoreboard")]
partial class Scoreboard : Node
{
    const string LaunchHint = "Press Space to launch";

    /// <summary>Goals the left paddle scored.</summary>
    [Export] public partial int Left { get; set; }

    /// <summary>Goals the right paddle scored.</summary>
    [Export] public partial int Right { get; set; }

    [On<GoalScored>]
    void OnGoal(GoalScored goal)
    {
        if (goal.LeftScored) Left++;
        else Right++;
        Show("ScoreLeft", Left.ToString());
        Show("ScoreRight", Right.ToString());
        Show("ScoreHint", LaunchHint);
    }

    [On<BallLaunched>]
    void OnLaunched(BallLaunched _) => Show("ScoreHint", "");

    void Show(string child, string text) => Child<LabelComponent>(child).Text = text;
}
