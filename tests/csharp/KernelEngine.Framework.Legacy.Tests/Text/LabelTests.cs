using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class LabelTests
{
    [Fact]
    public void Start_RegistersInStaticSnapshot()
    {
        var label = new Label();
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        
        startMethod!.Invoke(label, null);

        var snapshot = Label.Snapshot();
        Assert.Contains(label, snapshot);

        // Cleanup
        var onDestroyMethod = typeof(Node).GetMethod("OnDestroy", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        onDestroyMethod!.Invoke(label, null);
    }

    [Fact]
    public void OnDestroy_UnregistersFromStaticSnapshot()
    {
        var label = new Label();
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(label, null);

        var onDestroyMethod = typeof(Node).GetMethod("OnDestroy", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        onDestroyMethod!.Invoke(label, null);

        var snapshot = Label.Snapshot();
        Assert.DoesNotContain(label, snapshot);
    }
}
