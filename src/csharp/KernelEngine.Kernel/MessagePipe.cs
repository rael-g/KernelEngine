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

    public MessagePipe(Allocator allocator, Logger? logger)
    {
        ke_message_pipe* native;
        var res = NativeMethods.message_pipe_create(
            allocator.Native,
            logger != null ? logger.Native : null,
            &native);

        KernelException.ThrowIfFailed(res, nameof(NativeMethods.message_pipe_create));
        _native = native;
    }

    internal MessagePipe(ke_message_pipe* native) => _native = native;

    public void Broadcast<T>(ulong messageId, T value) where T : unmanaged
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->broadcast(_native, messageId, &value, (nuint)sizeof(T));
    }

    public bool TryReceive<T>(ulong messageId, out T value) where T : unmanaged
    {
        T tmp = default;
        bool received = _native->try_receive(_native, messageId, &tmp, (nuint)sizeof(T));
        value = tmp;
        return received;
    }

    public void Pump()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->pump(_native);
    }

    public static Result<MessagePipe> CreateReader(MessagePipe pipe)
    {
        ke_message_pipe* reader;
        var res = pipe.Native->create_reader(pipe.Native, &reader);
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
