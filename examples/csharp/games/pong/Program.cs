using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── Pong (2D) ─────────────────────────────────────────────────────────────────
// Game-specific code lives in:
//   • PongAction.cs / Paddle.cs / Ball.cs / Field.cs — the scripts
//   • scenes/*.scene + Project + actions.input + assets/    — the data
//
// Program.cs is just the bootstrap: which backends to wire. Every line is a parameterless
// registration; per-game parameters (window size, gravity, log level, action enum) come from
// Project / actions.input / [GameActions] attribute discovery. When the CLI editor (Tier P P3)
// lands, this file becomes fully auto-generated from the reference manifest.

var services = new ServiceCollection()
    .AddKernel()
    .AddProjectConfig()
    .AddLogger().AddConsoleSink()
    .AddInput()
    .AddInputActions()
    .AddGlfwWindow()
    .AddBgfxRenderer()
    .AddBox2D()
    .AddMiniAudio()
    .AddAudioFramework()
    .AddTextStbTrueType();

using var app = new Application();
app.Run(services);
