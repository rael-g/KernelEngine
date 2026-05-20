using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using KernelEngine.Asset.Assimp;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 12 Asset Loading")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddAssimpAssetLoader();

using var app = new Application();

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 12_asset_loading");
    Console.WriteLine("[KernelEngine] Features: assimp_loader, model_to_scene");

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 2f, 5f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Lights
    app.Scene.AddNode(
        new LightNode { Color = Vector3.One, Intensity = 3.0f },
        "Sun").LocalTransform = new Transform { Position = new Vector3(5f, 10f, 5f) };

    // Load model via the IAssetLoader abstraction (concrete Assimp loader is hidden behind DI),
    // then upload to GPU + build the scene by hand. A one-call AddToScene helper is planned in
    // docs/Kanban.md [B5.6] (KernelEngine.AssetPipeline); for now the raw 3-step pattern is explicit.
    var loader = app.Services.GetRequiredService<IAssetLoader>();

    try {
        string modelPath = Path.Combine(AppContext.BaseDirectory, "../../../../../assets/Box.gltf");
        Console.WriteLine($"[KernelEngine] Loading model: {modelPath}");

        using var modelData = await loader.LoadModelAsync(modelPath);
        Console.WriteLine($"[KernelEngine] Model loaded: {modelData.Meshes.Count} meshes, {modelData.Materials.Count} materials");

        // 1) Upload each decoded texture to the GPU.
        var gpuTextures = new TextureHandle[modelData.Textures.Count];
        for (int i = 0; i < modelData.Textures.Count; i++)
        {
            var tex = modelData.Textures[i];
            gpuTextures[i] = await resources.CreateTextureAsync(tex.Width, tex.Height, tex.Pixels.ToArray());
        }

        // 2) Build a GPU material per material slot, wiring in albedo + normal textures.
        var gpuMaterials = new MaterialHandle[modelData.Materials.Count];
        for (int i = 0; i < modelData.Materials.Count; i++)
        {
            var mat = modelData.Materials[i];
            var albedo = mat.AlbedoTextureIndex >= 0 ? gpuTextures[mat.AlbedoTextureIndex] : default;
            var normal = mat.NormalMapTextureIndex >= 0 ? gpuTextures[mat.NormalMapTextureIndex] : default;
            gpuMaterials[i] = await resources.CreateMaterialAsync(
                mat.BaseColor, textureHandle: albedo,
                metallic: mat.Metallic, roughness: mat.Roughness,
                normalMapHandle: normal);
        }

        // 3) Upload each mesh and attach a MeshNode under a single root (flat — Assimp hierarchy is lost).
        var modelRoot = app.Scene.AddNode("Box");
        for (int i = 0; i < modelData.Meshes.Count; i++)
        {
            var meshData = modelData.Meshes[i];
            var gpuMesh = await resources.CreateMeshAsync(
                meshData.Vertices.ToArray(),
                meshData.Indices.ToArray());
            var material = meshData.MaterialIndex >= 0 ? gpuMaterials[meshData.MaterialIndex] : default;
            app.Scene.AddNode(
                new MeshNode { MeshHandle = gpuMesh, MaterialHandle = material },
                meshData.Name, parent: modelRoot);
        }
        modelRoot.LocalTransform = modelRoot.LocalTransform with { Scale = new Vector3(1.0f) };
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[KernelEngine] ERROR loading model: {ex.Message}");
    }
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    scene.SetAmbientLight(0.05f, 0.05f, 0.05f);
};

app.Run(services);
