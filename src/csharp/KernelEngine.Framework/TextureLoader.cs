using KernelEngine;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace KernelEngine.Framework;

/// <summary>
/// Utility for loading image files into GPU textures via <see cref="Renderer.CreateTexture"/>.
/// Decodes to RGBA8 using SixLabors.ImageSharp (cross-platform, no GDI+ dependency).
/// </summary>
public static class TextureLoader
{
    /// <summary>
    /// Loads a PNG (or any ImageSharp-supported format) from <paramref name="path"/>,
    /// uploads it to the GPU, and returns a stable texture handle.
    /// </summary>
    public static uint LoadFile(Renderer renderer, string path)
    {
        using var image = Image.Load<Rgba32>(path);
        var pixels = new byte[image.Width * image.Height * 4];
        image.CopyPixelDataTo(pixels);
        return renderer.CreateTexture((uint)image.Width, (uint)image.Height, pixels);
    }

    /// <summary>
    /// Decodes image data from a stream and uploads it to the GPU.
    /// </summary>
    public static uint LoadStream(Renderer renderer, Stream stream)
    {
        using var image = Image.Load<Rgba32>(stream);
        var pixels = new byte[image.Width * image.Height * 4];
        image.CopyPixelDataTo(pixels);
        return renderer.CreateTexture((uint)image.Width, (uint)image.Height, pixels);
    }

    /// <summary>
    /// Loads 6 image files and uploads them as a GPU cubemap, returning a stable handle.
    /// <paramref name="facePaths"/> must be exactly 6 paths ordered: +X, -X, +Y, -Y, +Z, -Z.
    /// All images must be square and the same size.
    /// </summary>
    public static uint LoadCubemapFiles(Renderer renderer, string[] facePaths)
    {
        if (facePaths.Length != 6)
            throw new ArgumentException("Exactly 6 face paths required (+X,-X,+Y,-Y,+Z,-Z).", nameof(facePaths));

        using var img0 = Image.Load<Rgba32>(facePaths[0]);
        uint faceSize = (uint)img0.Width;
        uint faceBytes = faceSize * faceSize * 4;
        var combined = new byte[6 * faceBytes];

        for (int i = 0; i < 6; i++)
        {
            using var face = Image.Load<Rgba32>(facePaths[i]);
            face.CopyPixelDataTo(combined.AsSpan((int)(i * faceBytes), (int)faceBytes));
        }

        return renderer.CreateCubemap(faceSize, combined);
    }
}
