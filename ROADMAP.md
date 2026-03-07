# KernelEngine — Graphics Roadmap

## Rendering features — status

| Feature | Status |
|---------|--------|
| Camera (FoV, near/far, view/proj matrix) | Done |
| Mesh resource (VBO/IBO, ke_vertex with tangent) | Done |
| Material (albedo color + texture, metallic, roughness, normal map) | Done |
| Directional light (PBR Cook-Torrance GGX) | Done |
| Point lights — Clustered Forward | Done |
| Spot lights — Clustered Forward | Done |
| Clustered Forward Shading (dynamic grid, unlimited lights) | Done |
| Texture loading (RGBA8, CPU mipmaps via box filter) | Done |
| Normal maps (TBN, tangent-space) | Done |
| PBR shader (metallic/roughness workflow, F0, GGX BRDF) | Done |
| IBL / Skybox (cubemap, diffuse + specular split-sum) | Done |
| Shadow maps (depth pass, PCF bias) | Done |
| HDR Tonemapping (ACES, exposure, gamma) | Done |
| Bloom (bright-pass + Gaussian blur) | Done |
| SSAO (G-buffer prepass, hemisphere kernel, blur) | Done |
| Asset loader (Assimp glTF/OBJ + stb_image textures) | Done |
| MeshRendererComponent in C kernel | Done |
| Depth prepass (early-Z, overdraw reduction) | Pending |
| KTX2 / compressed textures | Pending |
| glTF binary bake (offline asset pipeline) | Pending |

---

## Examples

Examples live in `examples/csharp/`. Each one is an E2E test with two goals:
- **Visual feedback** for the developer (what is rendered on screen)
- **Log feedback** for automated review (what the engine reports at runtime)

Each example must log at startup: active features, resource counts, and any initialization errors.
Each example must log per-frame (every 5 s): FPS, entity count, light count.

### Complexity ladder

| # | Name | What it tests | Expected visual | Expected logs |
|---|------|---------------|-----------------|---------------|
| 01 | `01_window_scene` | Window, clear color, main loop, spinning node | Cycling background color, rotating orange quad | SpinnerNode started, frame delta |
| 02 | `02_textured_quad` | Texture loading (PNG), albedo material, UV mapping | Quad with a PNG image | Texture handle created, image dimensions |
| 03 | `03_pbr_directional` | PBR shader, directional light, camera orbit | Lit sphere/cube with specular highlight moving with light | Light direction, metallic/roughness values |
| 04 | `04_normal_map` | Normal map pipeline, TBN, tangent-space | Brick-like surface with depth illusion from a flat quad | Normal map handle created, u_normalParams active |
| 05 | `05_skybox_ibl` | Cubemap loading, skybox rendering, IBL reflections | Reflective sphere inside a skybox | Cubemap faces loaded, IBL active |
| 06 | `06_shadow_map` | Shadow map pass, depth bias, shadow receiving | Hard shadow cast by a box onto a ground plane | Shadow map dimensions, light VP matrix |
| 07 | `07_point_lights` | Clustered Forward with N point lights | Multiple colored point lights illuminating a scene | Cluster grid config, light count, FPS with N=64 |
| 08 | `08_spot_lights` | Spot lights with inner/outer cone falloff | Flashlight-style cone illumination | Spot count, cosInner/cosOuter values |
| 09 | `09_many_lights` | Clustered scaling — 256 point lights | Dense field of colored lights with no visible cap | Light count=256, cluster culling active, stable FPS |
| 10 | `10_postfx` | HDR tonemapping + bloom | Bright emissive areas bleeding into surrounding pixels | Tonemapping enabled, exposure/gamma, bloom threshold |
| 11 | `11_ssao` | SSAO prepass, hemisphere kernel, AO blending | Ambient occlusion darkening crevices and corners | SSAO radius/bias/strength, kernel size |
| 12 | `12_asset_loader` | Assimp glTF load, texture deduplication, mesh upload | A glTF model (e.g. DamagedHelmet) rendered with PBR materials | Model path, mesh count, material count, texture count |
| 13 | `13_full_scene` | Everything combined | glTF model inside a skybox, shadow, 32 point lights, SSAO, bloom | All feature flags active, FPS >= 30 at 1080p |

### Log contract (all examples)

At startup each example must print:
```
[KernelEngine] Example: <name>
[KernelEngine] Renderer: bgfx/Vulkan
[KernelEngine] Features: <comma-separated list of active features>
```

Every 5 seconds:
```
[KernelEngine] FPS: <value>  Entities: <count>  Lights: <point>p <spot>s <dir>d
```

On error (any ke_result != KE_OK):
```
[KernelEngine] ERROR: <function> returned <code>
```

---

## Remaining tasks

- Depth prepass (early-Z): always-on geometry pass before main scene, share depth with HDR framebuffer for DEPTH_TEST_EQUAL optimization
- KTX2 support: GPU-compressed textures with embedded mipmaps (BC7/ASTC)
- Offline asset pipeline: bake glTF + PNG → engine binary format at build time

---

## Observabilidade — plano de refatoração

### Objetivo

Com `KE_LOG_LEVEL_DEBUG` ativo, o log deve ser suficiente para reconstruir a sequência de eventos que levou à falha do programa, sem necessidade de debugger. Atualmente o sistema tem quatro pontos de silêncio estrutural descritos abaixo.

### Crashes conhecidos e status

| Sintoma | Causa | Status |
|---------|-------|--------|
| Exit `0x80000003`, sem log | `bgfx::setBuffer()` antes de `bgfx::submit()` — API compute usada em draw call | **Corrigido** — substituído por `setUniform` |
| Exit silencioso na raiz do repo | Shaders compilados no Linux, SPIRV incompatível com driver Vulkan Windows | **Corrigido** — recompilado com `shaderc.exe` local |
| "Failed to load scene shaders" | Shader path relativo ao CWD | **Corrigido** — `AppContext.BaseDirectory` + `Directory.Build.targets` |

### Ponto de silêncio 1 — bgfx não fala com o logger

**Problema:** bgfx possui `bgfx::CallbackI` com `fatal()` e `traceVargs()`. Sem implementação, `fatal()` chama `debugBreak()` diretamente e o processo termina com `0x80000003` sem nenhuma linha de log. `traceVargs()` descarta validação de API, avisos de shader e vazamentos de recurso.

**Tarefa DB-01:** Implementar `BgfxLogCallback : bgfx::CallbackI` em `bgfx_render_system.cc`.
- Campo `ke_logger* logger_` injetado no construtor
- `fatal(filePath, line, code, str)` → emite `KE_LOG_LEVEL_ERROR` com código bgfx, arquivo, linha e mensagem; depois chama `abort()` (não `debugBreak()`) para garantir exit code 3 e flush do log
- `traceVargs(filePath, line, format, argList)` → formata com `vsnprintf` e emite `KE_LOG_LEVEL_DEBUG` com tag `"bgfx"`
- Em `OnInitialize()`, atribuir `init.callback = &callback_` antes de `bgfx::init(init)`
- Em builds sem `NDEBUG`, setar `init.debug = true` para ativar validação interna e `VK_LAYER_KHRONOS_validation`

**Critério de aceite:** o erro de `setBuffer+submit` (que causou o crash) deve aparecer no log como linha `[ERROR][bgfx] ...` antes da terminação, sem abrir o debugger.

---

### Ponto de silêncio 2 — ke_result falha sem log em C++

**Problema:** em `bgfx_render_system.cc`, a maioria dos caminhos de erro retorna `KE_ERROR_*` sem emitir log. O chamador C# recebe o código mas não sabe de qual função nem com quais argumentos.

Exemplos reais:
- `if (!bgfx::isValid(...)) return KE_ERROR_RENDER;` — sem log
- `if (material >= materials_.size()) return KE_ERROR_INVALID_ARGUMENT;` — sem log

**Tarefa DB-02:** Criar helper `LogErr` local em `bgfx_render_system.cc`:
```
ke_result LogErr(ke_logger*, ke_result, const char* context, const char* detail)
```
Emite `KE_LOG_LEVEL_ERROR` com `context` e `detail`, retorna `r`. Substituir todos os `return KE_ERROR_*` que possuem `logger_` disponível.

**Tarefa DB-03:** Em `OnInitialize()`, adicionar log `KE_LOG_LEVEL_DEBUG` para cada etapa:
- Shader path resolvido e se o arquivo existe
- Resultado de cada `load_shader()` (nome + valid/invalid)
- Resultado de cada `createUniform()`, `createFrameBuffer()`
- Ao final: GPU name via `bgfx::getCaps()->vendorId`, renderer type

**Critério de aceite:** com `KE_LOG_LEVEL_DEBUG`, uma falha de shader load produz linha como `[DEBUG][bgfx] load_shader("fs_basic"): NOT FOUND at path/shaders/fs_basic.bin`.

---

### Ponto de silêncio 3 — C# engole contexto das exceções

**Problema:** `KernelException.ThrowIfFailed(ke_result)` lança com apenas o valor inteiro. Callers no framework descartam resultados com `_ = renderer.Method()` sem logar falhas.

**Tarefa DB-04:** Enriquecer `KernelException`:
- Adicionar `static readonly Dictionary<int, string> ResultNames` mapeando cada valor `ke_result` ao nome simbólico (`KE_ERROR_RENDER`, `KE_ERROR_NOT_INITIALIZED`, etc.)
- `ThrowIfFailed(ke_result r, string context = "")` — mensagem: `"KE_ERROR_RENDER in Renderer.SubmitMesh"`

**Tarefa DB-05:** Auditar todos os `_ = ` em `KernelEngine.Framework`. Para cada um: ou logar via `ILogger` quando o resultado for falha, ou substituir por `KernelException.ThrowIfFailed(result, nameof(método))`.

**Tarefa DB-06:** Em `Application.Run()`, envolver o loop principal em `try/catch(Exception ex)` que loga via logger antes de relançar. O objetivo é garantir que exceções C# apareçam no log mesmo se o sink não fizer flush automático no unwind.

**Critério de aceite:** um `ke_result` que falhe em qualquer ponto do framework produz linha de log com nome simbólico e função de origem antes de propagar.

---

### Ponto de silêncio 4 — crash nativo bypassa tudo

**Problema:** quando bgfx chama `debugBreak()` ou ocorre access violation na DLL, o processo termina via SEH (Windows Structured Exception Handling). Nesse momento: nenhum `finally` do C# executa, `AppDomain.UnhandledException` não dispara para SEH nativo, o log não é flushado se o sink usar buffer.

**Tarefa DB-07:** Garantir flush síncrono nos sinks. Em `ConsoleSink` e `SerilogSink`, verificar que `Log()` escreve diretamente sem buffering. Se houver buffer, adicionar `Flush()` ao final de cada `Log()` call.

**Tarefa DB-08:** Em `Application.Run()`, registrar `SetUnhandledExceptionFilter` via P/Invoke antes de iniciar o loop:
- Captura o código SEH (`ExceptionCode` do `EXCEPTION_RECORD`)
- Escreve via `Console.Error.WriteLine` (não via logger — estado pode estar corrompido): `[FATAL] Native crash SEH 0x80000003 (STATUS_BREAKPOINT)`
- Mapear os códigos mais comuns: `0x80000003` = bgfx assert, `0xC0000005` = access violation, `0xC00000FD` = stack overflow
- Chamar `Environment.Exit(1)` para garantir código 1 no terminal

**Critério de aceite:** executar o binário com o bug original (setBuffer+submit) produz `[FATAL] Native crash SEH 0x80000003 (STATUS_BREAKPOINT — bgfx debug assert)` em stderr antes de terminar.

---

### Ordem de execução

| Ordem | Tarefa | Impacto | Esforço |
|-------|--------|---------|---------|
| 1 | DB-01 — BgfxLogCallback | Elimina silêncio do crash mais grave | Médio |
| 2 | DB-07 — Flush síncrono nos sinks | Garante que logs aparecem antes da morte | Baixo |
| 3 | DB-08 — SetUnhandledExceptionFilter | Torna crashes nativos visíveis no terminal | Médio |
| 4 | DB-02 — LogErr em ke_result C++ | Localiza falhas de inicialização e render | Médio |
| 5 | DB-03 — Logs DEBUG em OnInitialize | Permite diagnóstico de boot sem debugger | Baixo |
| 6 | DB-04 — ThrowIfFailed com nomes simbólicos | Melhora mensagens C# | Baixo |
| 7 | DB-05 — Audit de `_ =` no framework | Elimina resultados silenciosamente descartados | Baixo |
| 8 | DB-06 — try/catch no loop principal | Garante flush em exceções C# | Baixo |
