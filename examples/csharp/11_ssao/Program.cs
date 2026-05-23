using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 24-vertex unit cube (4 verts/face) with per-face normals — gives real occlusion for SSAO.
static (Vertex[] verts, ushort[] idx) BuildCube()
{
    var v = new System.Collections.Generic.List<Vertex>(24);
    void AddFace(Vector3 n, Vector3 t, Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)
    {
        v.Add(new Vertex { X=p0.X,Y=p0.Y,Z=p0.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=0,V=0, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
        v.Add(new Vertex { X=p1.X,Y=p1.Y,Z=p1.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=1,V=0, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
        v.Add(new Vertex { X=p2.X,Y=p2.Y,Z=p2.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=1,V=1, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
        v.Add(new Vertex { X=p3.X,Y=p3.Y,Z=p3.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=0,V=1, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
    }
    AddFace(new(1,0,0),  new(0,0,-1), new(0.5f,-0.5f,0.5f), new(0.5f,-0.5f,-0.5f), new(0.5f,0.5f,-0.5f), new(0.5f,0.5f,0.5f));
    AddFace(new(-1,0,0), new(0,0,1),  new(-0.5f,-0.5f,-0.5f), new(-0.5f,-0.5f,0.5f), new(-0.5f,0.5f,0.5f), new(-0.5f,0.5f,-0.5f));
    AddFace(new(0,1,0),  new(1,0,0),  new(-0.5f,0.5f,0.5f), new(0.5f,0.5f,0.5f), new(0.5f,0.5f,-0.5f), new(-0.5f,0.5f,-0.5f));
    AddFace(new(0,-1,0), new(1,0,0),  new(-0.5f,-0.5f,-0.5f), new(0.5f,-0.5f,-0.5f), new(0.5f,-0.5f,0.5f), new(-0.5f,-0.5f,0.5f));
    AddFace(new(0,0,1),  new(1,0,0),  new(-0.5f,-0.5f,0.5f), new(0.5f,-0.5f,0.5f), new(0.5f,0.5f,0.5f), new(-0.5f,0.5f,0.5f));
    AddFace(new(0,0,-1), new(-1,0,0), new(0.5f,-0.5f,-0.5f), new(-0.5f,-0.5f,-0.5f), new(-0.5f,0.5f,-0.5f), new(0.5f,0.5f,-0.5f));
    var idx = new ushort[36];
    for (ushort f = 0; f < 6; f++) { ushort b=(ushort)(f*4); idx[f*6+0]=b; idx[f*6+1]=(ushort)(b+1); idx[f*6+2]=(ushort)(b+2); idx[f*6+3]=b; idx[f*6+4]=(ushort)(b+2); idx[f*6+5]=(ushort)(b+3); }
    return (v.ToArray(), idx);
}

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 11 SSAO")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 11_ssao");
    Console.WriteLine("[KernelEngine] Features: ssao, gbuffer_prepass");

    // Camera
    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    // The camera looks down its local -Z (no Camera.LookAt helper yet — framework gap).
    // Orient it manually toward the cube wall for a 3/4 angle that frames wall + floor + SSAO.
    var eye = new Vector3(6f, 5f, 9f);
    var lookRot = Quaternion.CreateFromRotationMatrix(
        Matrix4x4.CreateWorld(eye, Vector3.Normalize(new Vector3(0f, 2f, 0f) - eye), Vector3.UnitY));
    cam.LocalTransform = cam.LocalTransform with { Position = eye, Rotation = lookRot };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Materials
    var mat = resources.CreateMaterial(new Vector4(0.7f, 0.7f, 0.7f, 1f), metallic: 0.0f, roughness: 0.5f);

    // Directional light so surfaces are lit (without it the Tree is near-black and SSAO has
    // nothing to darken). Direction is the vector toward the light source.
    app.Tree.AddNode(
        new DirectionalLight { Direction = Vector3.Normalize(new Vector3(0.4f, 1f, 0.6f)), Color = Vector3.One, Intensity = 4.0f },
        "Sun");

    // Real cube mesh — flat quads don't occlude each other, so SSAO needs actual geometry.
    var (cubeVerts, cubeIdx) = BuildCube();
    var cubeMesh = resources.CreateMesh(cubeVerts, cubeIdx);

    // Floor. Default mesh is a quad in the XY plane (normal +Z); rotate -90° about X to lay it flat.
    var floor = app.Tree.AddNode(new MeshRenderer { MaterialHandle = mat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with
    {
        Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitX, -MathF.PI / 2f),
        Scale = new Vector3(10f, 10f, 1f)
    };

    // Wall of cubes to see ambient occlusion in the contacts between them.
    for (int x = -3; x <= 3; x += 1)
    {
        for (int y = 1; y <= 4; y += 1)
        {
            var n = app.Tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = mat }, $"Cube_{x}_{y}");
            n.LocalTransform = n.LocalTransform with {
                Position = new Vector3(x, y, 0f),
                Scale = new Vector3(0.9f, 0.9f, 0.9f)
            };
        }
    }
};

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.2f, 0.2f, 0.2f, 1f);
    tree.SetAmbientLight(0.3f, 0.3f, 0.3f);
    // NOTE: SSAO is currently a NO-OP — PostProcessPipeline::SetupSsao is an unimplemented stub,
    // so no ambient-occlusion is produced. Until it's implemented, the contact darkening visible
    // here is the directional SHADOW MAP, not SSAO. (Tracked: Kanban OBS.4.)
    tree.SetSsao(true, radius: 0.5f, bias: 0.025f, strength: 2.0f);
};

app.Run(services);
