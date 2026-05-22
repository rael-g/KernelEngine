using System.Diagnostics;

namespace KernelEngine.Framework;

/// <summary>
/// Frame timing for game code. Driven by the simulation thread (ke.sim): the framework calls
/// <see cref="NewFrame"/> once at the top of each sim frame. Read <see cref="DeltaTime"/> in
/// <c>OnUpdate</c> / node callbacks. Modeled on the classic engine <c>Time</c> service.
/// </summary>
public static class Time
{
    /// <summary>Seconds since the timer started.</summary>
    public static float ElapsedTime => (float)_stopwatch.Elapsed.TotalSeconds;

    /// <summary>Seconds elapsed during the previous sim frame.</summary>
    public static float DeltaTime { get; private set; }

    private static readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    private static float _previousFrameTime;

    /// <summary>Called by the framework once per sim frame to advance <see cref="DeltaTime"/>.</summary>
    internal static void NewFrame()
    {
        var now = ElapsedTime;
        DeltaTime = now - _previousFrameTime;
        _previousFrameTime = now;
    }
}
