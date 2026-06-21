using System.Runtime.CompilerServices;

namespace KernelEngine.Scheduler;

/// <summary>
/// A fire-and-forget task dispatched to the native thread pool.
/// Supports <c>await</c> identically to <see cref="Task"/>.
/// </summary>
public sealed class KernelTask
{
    private readonly Task _inner;

    internal KernelTask(Task inner) => _inner = inner;

    /// <summary>Whether the task has finished executing.</summary>
    public bool IsCompleted => _inner.IsCompleted;

    /// <summary>Blocks the calling thread until the task completes.</summary>
    public void Wait() => _inner.GetAwaiter().GetResult();

    /// <inheritdoc cref="Task.GetAwaiter"/>
    public TaskAwaiter GetAwaiter() => _inner.GetAwaiter();
}

/// <summary>
/// A task dispatched to the native thread pool that produces a value of type <typeparamref name="T"/>.
/// Supports <c>await</c> identically to <see cref="Task{T}"/>.
/// </summary>
/// <typeparam name="T">The type of the result value.</typeparam>
public sealed class KernelTask<T>
{
    private readonly Task<T> _inner;

    internal KernelTask(Task<T> inner) => _inner = inner;

    /// <summary>Wraps an existing <see cref="Task{T}"/> as a <see cref="KernelTask{T}"/>.</summary>
    public static KernelTask<T> FromTask(Task<T> task) => new(task);

    /// <summary>Whether the task has finished executing.</summary>
    public bool IsCompleted => _inner.IsCompleted;

    /// <summary>
    /// Blocks the calling thread until the task completes and returns the result.
    /// Prefer <c>await</c> over this on the sim/render threads.
    /// </summary>
    public T Result => _inner.GetAwaiter().GetResult();

    /// <inheritdoc cref="Task{T}.GetAwaiter"/>
    public TaskAwaiter<T> GetAwaiter() => _inner.GetAwaiter();
}
