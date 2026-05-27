using KernelEngine.Framework.Animation;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class TimingTests
{
    [Fact]
    public async Task AfterAsync_ExecutesAction()
    {
        bool executed = false;
        Timing.AfterAsync(50, () => executed = true);
        
        await Task.Delay(200);
        Assert.True(executed);
    }

    [Fact]
    public async Task EveryAsync_ExecutesMultipleTimes()
    {
        int count = 0;
        using var cts = new CancellationTokenSource();
        var tcs = new TaskCompletionSource<bool>();
        
        Timing.EveryAsync(10, () => {
            count++;
            if (count >= 3) tcs.TrySetResult(true);
        }, cts.Token);
        
        // Wait for up to 1 second for 3 executions
        var completed = await Task.WhenAny(tcs.Task, Task.Delay(1000)) == tcs.Task;
        cts.Cancel();
        
        Assert.True(completed, $"Expected at least 3 executions, got {count}");
        Assert.True(count >= 3);
    }

    [Fact]
    public async Task EveryAsync_StopsOnCancellation()
    {
        int count = 0;
        using var cts = new CancellationTokenSource();
        
        Timing.EveryAsync(50, () => count++, cts.Token);
        await Task.Delay(30); // Give it a moment to start
        cts.Cancel();
        
        await Task.Delay(100);
        int countAtCancel = count;
        
        await Task.Delay(100);
        Assert.Equal(countAtCancel, count);
    }
}
