using KernelEngine.Framework;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class MeshShapeTests
{
    [Fact]
    public void Cube_Has24VerticesAnd36Indices()
    {
        var cube = MeshShape.Cube();
        Assert.Equal(24, cube.Vertices.Length); // 4 verts/face × 6 faces (per-face normals)
        Assert.Equal(36, cube.Indices.Length);  // 6 indices/face × 6 faces
    }

    [Fact]
    public void Quad_AndPlane_AreSingleQuads()
    {
        Assert.Equal(4, MeshShape.Quad().Vertices.Length);
        Assert.Equal(6, MeshShape.Quad().Indices.Length);
        Assert.Equal(4, MeshShape.Plane().Vertices.Length);
        Assert.Equal(6, MeshShape.Plane().Indices.Length);
    }

    [Fact]
    public void Sphere_RespectsSegmentCount()
    {
        var s = MeshShape.Sphere(8);
        int rings = 4; // segments / 2
        Assert.Equal((rings + 1) * (8 + 1), s.Vertices.Length);
        Assert.Equal(rings * 8 * 6, s.Indices.Length);
    }
}
