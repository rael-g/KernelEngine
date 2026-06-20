namespace KernelEngine.Kernel;

/// <summary>
/// Read-only view of a mesh loaded as part of an <see cref="IModel"/>.
/// Vertex/index spans are backed by the parent <see cref="IModel"/>'s memory.
/// </summary>
public interface IModelMesh
{
    /// <summary>Mesh name.</summary>
    string Name { get; }

    /// <summary>Index into <see cref="IModel.Materials"/>; <c>-1</c> = none.</summary>
    int MaterialIndex { get; }

    /// <summary>Vertices in the engine's standard <see cref="Vertex"/> layout.</summary>
    ReadOnlySpan<Vertex> Vertices { get; }

    /// <summary>Triangle index buffer.</summary>
    ReadOnlySpan<ushort> Indices { get; }
}
