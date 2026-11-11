using System.ComponentModel.DataAnnotations;

using KernelEngine.Framework.Nodes;

namespace Pong;

/// <summary>The match: serves on Launch, goes back to the menu on Quit, and keeps the score.</summary>
[NodeType("pong.match")]
partial class Match : Node
{
    /// <summary>The sound of a goal.</summary>
    [Export, MaxLength(256)] public partial string ScoreSound { get; set; }

    /// <summary>The goal's volume.</summary>
    [Export] public partial float ScoreVolume { get; set; }

    partial int Left { get; set; }

    partial int Right { get; set; }

    partial bool Serving { get; set; }

    public Match()
    {
        ScoreVolume = 1.0f;
        Serving = true;
    }

    void Update()
    {
        if (Pressed("Quit")) ChangeScene(Scenes.Menu);
        else if (Serving && Pressed("Launch"))
        {
            Serving = false;
            Raise(new ServeRequested { Requested = true });
        }
    }

    [On<GoalScored>]
    void OnGoal(GoalScored goal)
    {
        if (goal.LeftScored) Left++;
        else Right++;
        Serving = true;
        Raise(new ScoreChanged { Left = Left, Right = Right });
        Spawn("Sound", Sounds.Once(ScoreSound, ScoreVolume));
    }
}
