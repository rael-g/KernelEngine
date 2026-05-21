namespace KernelEngine.Kernel;

/// <summary>
/// Documentation attribute indicating that a method must only be called from a specific named thread.
/// In debug builds, these methods usually contain a <see cref="KernelThread.AssertCurrent"/> check.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Property, AllowMultiple = false)]
public sealed class RequiresThreadAttribute(string threadName) : Attribute
{
    public string ThreadName { get; } = threadName;
}
