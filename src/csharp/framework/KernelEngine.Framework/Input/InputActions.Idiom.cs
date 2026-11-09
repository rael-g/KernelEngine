namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to the native input action maps. This part declares the constructor that calls
/// the native factory; the members that mirror the vtable are generated.
/// </summary>
public unsafe partial class InputActions
{
    /// <summary>
    /// Creates the action maps, adding those the <c>input</c> section of
    /// <paramref name="configuration"/> describes; with no configuration there is no map, and a
    /// program adds its own through <see cref="AddMap"/> and <see cref="AddAction"/>.
    /// </summary>
    /// <exception cref="InvalidOperationException">The native factory fails, such as for a key
    /// name the configuration misspells.</exception>
    public InputActions(KernelEngine.Configuration.INativeConfiguration? configuration = null) : this(Create(configuration))
    {
        if (configuration is not null) Hold(configuration.Owner);
    }

    private static ke_input_actions_handle Create(KernelEngine.Configuration.INativeConfiguration? configuration)
    {
        ke_input_actions_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.input_actions_create(null, null, configuration is null ? null : configuration.Native, null, &handle), "ke_input_actions_create");
        return handle;
    }
}
