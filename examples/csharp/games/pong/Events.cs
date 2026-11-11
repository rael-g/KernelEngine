namespace Pong;

/// <summary>The ball crossed a goal line.</summary>
struct GoalScored
{
    public bool LeftScored;
}

/// <summary>The match asks the ball to be served.</summary>
struct ServeRequested
{
    public bool Requested;
}

/// <summary>The score after a goal.</summary>
struct ScoreChanged
{
    public int Left;
    public int Right;
}
