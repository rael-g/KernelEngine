namespace KernelEngine.Ecs;

/// <summary>
/// Zero-copy query result from <see cref="EcsRegistry.Query{T}"/>.
/// Valid until the next structural change (add/remove component).
/// </summary>
public ref struct EcsQuery<T> where T : unmanaged
{
    public ReadOnlySpan<ulong> Entities { get; }
    public Span<T> Data { get; }
    public int Length => Entities.Length;

    public EcsQuery(ReadOnlySpan<ulong> entities, Span<T> data)
    {
        Entities = entities;
        Data = data;
    }

    public void Deconstruct(out ReadOnlySpan<ulong> entities, out Span<T> data)
    {
        entities = Entities;
        data = Data;
    }
}
