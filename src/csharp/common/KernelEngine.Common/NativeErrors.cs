using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine;

/// <summary>
/// Crosses a native failure into the exception that stands for its category, and a managed exception
/// back into a native error record. Which exception a native error name becomes is declared in the
/// manifest and generated into <c>NativeErrors.Kinds.g.cs</c>; a failure whose type chain names none of
/// them becomes the general one. The native cause chain becomes <see cref="Exception.InnerException"/>, the source location is part of the
/// message, and the full native type name is kept in <see cref="Exception.Data"/> under
/// <see cref="TypeKey"/>.
/// </summary>
public static unsafe partial class NativeErrors
{
    /// <summary>The <see cref="Exception.Data"/> key that holds the dotted name of the native error type.</summary>
    public const string TypeKey = "ke.error_type";

    /// <summary>The exception that stands for a native error.</summary>
    /// <param name="error">The native record, or null when the call failed without detail.</param>
    /// <param name="context">The name of the call, prefixed to the message.</param>
    public static Exception FromNative(ke_error* error, string? context = null)
    {
        if (error is null)
            return new InvalidOperationException(Prefix(context, "native call failed without error detail"));

        var typeName = Name(error->type);
        var message = error->message is not null
            ? Marshal.PtrToStringUTF8((nint)error->message) ?? ""
            : typeName ?? "native error";
        if (error->file is not null)
            message += $" ({Marshal.PtrToStringUTF8((nint)error->file)}:{error->line})";
        message = Prefix(context, message);
        var cause = error->cause is not null ? FromNative(error->cause) : null;

        var exception = Create(error->type, message, cause);
        if (typeName is not null) exception.Data[TypeKey] = typeName;
        return exception;
    }

    /// <summary>Throws the exception for <paramref name="error"/> when <paramref name="ok"/> is false.</summary>
    public static void ThrowIfFailed(bool ok, ke_error* error, string? context = null)
    {
        if (!ok)
            throw FromNative(error, context);
    }

    /// <summary>Writes <paramref name="exception"/> into a native error lane; only its message crosses.</summary>
    public static void ToNative(ke_error** outError, Exception exception, string? context = null)
    {
        if (outError is null) return;
        var text = System.Text.Encoding.UTF8.GetBytes(Prefix(context, exception.Message));
        var message = new byte[text.Length + 1];
        text.CopyTo(message, 0);
        fixed (byte* p = message)
            NativeMethods.error_set(outError, null, (sbyte*)p, null, 0, null);
    }

    static Exception Create(ke_error_type* type, string message, Exception? cause)
    {
        for (var t = type; t is not null; t = t->parent)
            if (Name(t) is { } name && TryCreate(name, message, cause, out var exception))
                return exception;
        return CreateGeneral(message, cause);
    }

    static string? Name(ke_error_type* type) =>
        type is not null && type->name is not null ? Marshal.PtrToStringUTF8((nint)type->name) : null;

    static string Prefix(string? context, string message) =>
        string.IsNullOrEmpty(context) ? message : $"{context}: {message}";
}
