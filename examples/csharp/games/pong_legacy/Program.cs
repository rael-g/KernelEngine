using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Configuration;
using KernelEngine.Window.Glfw;
using KernelEngine.Render.Bgfx;
using KernelEngine.Physics.Box2D;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Logger;
using KernelEngine.Audio;

var services = new ServiceCollection().AddNativeFramework().AddLogger().AddConsoleSink().AddInput().AddProjectConfig().AddInputActions().AddGlfwWindow().AddBgfxRenderer().AddBox2D().AddMiniAudio().AddAudioFramework().AddTextStbTrueType();
using var app = new Application();
app.Run(services);