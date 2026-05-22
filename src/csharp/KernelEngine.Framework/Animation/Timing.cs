namespace KernelEngine.Framework.Animation;

/// <summary>Fire-and-forget timed helpers built on <see cref="Task.Delay(int, CancellationToken)"/>.</summary>
public static class Timing
{
    /// <summary>Runs <paramref name="action"/> every <paramref name="interval"/> milliseconds until cancelled.</summary>
    public static async void EveryAsync(int interval, Action action, CancellationToken cancellationToken = default)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await Task.Delay(interval, cancellationToken);
            if (cancellationToken.IsCancellationRequested) break;
            action();
        }
    }

    /// <summary>Runs <paramref name="action"/> once after <paramref name="interval"/> milliseconds.</summary>
    public static async void AfterAsync(int interval, Action action, CancellationToken cancellationToken = default)
    {
        await Task.Delay(interval, cancellationToken);
        action();
    }
}
