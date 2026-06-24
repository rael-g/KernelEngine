namespace KernelEngine.Render;

/// <summary>
/// Uploads CPU mesh data to GPU buffers owned by the active render backend,
/// returning a <see cref="MeshHandle"/> a <see cref="MeshComponent"/> references.
/// The v2 render module implements this over the render core's mesh storage;
/// scene code (primitives, asset loaders) depends on this abstraction rather
/// than a concrete backend.
/// </summary>
public interface IMeshUploader
{
    /// <summary>
    /// Uploads interleaved position+normal vertices and 16-bit indices.
    /// Throws on failure — a bad upload is never swallowed. Call from the render
    /// worker (GPU resource creation has thread affinity).
    /// </summary>
    MeshHandle UploadMesh(ReadOnlySpan<MeshVertex> vertices, ReadOnlySpan<ushort> indices);
}
