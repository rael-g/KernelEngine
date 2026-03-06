using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Async message broadcast/receive channel between engine systems.
/// </summary>
public sealed unsafe class MessagePipe : IDisposable
{
    private ke_message_pipe* _native;

    public ke_message_pipe* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    private MessagePipe(ke_message_pipe* native) => _native = native;

    /// <summary>Creates a new message pipe using the given allocator.</summary>
    public MessagePipe(Allocator allocator, Logger? logger = null)
    {
        ke_message_pipe* pipe;
        // In constructor we still throw because if creation fails, the object is unusable.
        KernelException.ThrowIfFailed(NativeMethods.message_pipe_create(allocator.Native, logger != null ? logger.Native : null, &pipe));
        _native = pipe;
    }

    /// <summary>
    /// Moves all pending broadcast messages into reader queues.
    /// Call once per frame before any <see cref="TryReceive{T}"/> calls.
    /// </summary>
    public Result Pump() => _native->pump(_native);

    /// <summary>Broadcasts an unmanaged value to all readers.</summary>
    public Result Broadcast<T>(ulong messageId, T value) where T : unmanaged =>
        _native->broadcast(_native, messageId, &value, (nuint)sizeof(T));

    /// <summary>
    /// Attempts to dequeue one message of the given type.
    /// Returns <see langword="true"/> and populates <paramref name="value"/> if a message was available.
    /// </summary>
    public bool TryReceive<T>(ulong messageId, out T value) where T : unmanaged
    {
        T tmp = default;
        bool received = _native->try_receive(_native, messageId, &tmp, (nuint)sizeof(T));
        value = tmp;
        return received;
    }

    /// <summary>Creates a reader pipe that receives a copy of every message broadcast on this pipe.</summary>
    public Result<MessagePipe> CreateReader()
    {
        ke_message_pipe* reader;
        var res = _native->create_reader(_native, &reader);
        return new Result<MessagePipe>(res, new MessagePipe(reader));
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
