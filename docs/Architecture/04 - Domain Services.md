# Architecture Vision: Domain Roles

## 1. Platform Abstraction (Windowing)
The Windowing role serves as the bridge between the Kernel and the underlying Operating System.
*   **Responsibility**: Managing native window handles, handling OS event queues, and providing a surface for visual output.
*   **Goal**: Isolate the engine from platform-specific boilerplate.

## 2. Visual Output (Rendering)
The Rendering role is responsible for transforming high-level intent into pixels.
*   **Responsibility**: Orchestrating GPU resources, executing draw commands, and managing the visual state.
*   **Abstraction**: The engine interacts with an abstract rendering interface, allowing for different backends (DirectX, Vulkan, etc.) without changing the core simulation logic.

## 3. Interaction (Input)
The Input role tracks the state of user interaction devices.
*   **Responsibility**: Decoding hardware events (keyboard, mouse, controllers) into an immutable snapshot that the simulation can query safely.
*   **Flow**: Input state is captured once per OS tick into a `ke_input_snapshot` and handed to the simulation via a lock-free exchange. The simulation reads a frozen, consistent view of input for the entire duration of a frame.

## 4. Production Pipeline (Shader Compilation)
This role supports the rendering process by preparing hardware-ready programs.
*   **Responsibility**: Converting cross-platform shader descriptions into binary formats.
*   **Context**: By keeping this as a separate role, the engine can support both runtime hot-reloading for developers and pre-compiled optimized assets for production.
