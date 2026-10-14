namespace KernelEngine.Runtime;

/// <summary>
/// Documentation attribute indicating that a method must only be called from a specific named thread.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Property, AllowMultiple = false)]
public sealed class RequiresThreadAttribute(string threadName) : Attribute
{
    /// <summary>The name of the thread the member must be called from.</summary>
    public string ThreadName { get; } = threadName;
}
