namespace Pong;

/// <summary>
/// Raised by the ball when it crosses a goal line. The ball names the event and
/// nothing else — which node keeps score is wired in the scene, so the two never
/// have to know each other.
/// </summary>
/// <param name="LeftScored">True when the point went to the left player.</param>
public readonly record struct GoalScored(bool LeftScored);
