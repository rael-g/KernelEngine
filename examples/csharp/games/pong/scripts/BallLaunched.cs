namespace Pong;

/// <summary>
/// Raised by the ball the moment it leaves centre. Carries nothing: the fact that
/// play started is the whole message, and anything a listener needs beyond that is
/// its own state.
/// </summary>
public readonly record struct BallLaunched;
