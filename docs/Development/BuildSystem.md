# Build System Design

This document describes architectural decisions regarding project structure, build system, and integration strategy for a C++ project. The design is centered around three main requirements:
1.  **Modularity:** The project should be structured to allow independent development and testing of components.
2.  **Cross-Platform Compatibility:** The build system must support compilation on multiple operating systems (e.g., Windows, Linux).
3.  **Dependency Management:** A clear and efficient strategy for managing external libraries.

---

## 1. Directory Structure

A monorepo structure is often used to keep all related code and scripts in a single location. The management of external C++ libraries can be handled by `vcpkg`, making a dedicated `external/` directory unnecessary.

```
/project-root/
├── .gitignore
├── CMakeLists.txt            # Primary C++ build orchestrator with CMake.
├── CMakePresets.json         # Standardized build configurations.
├── vcpkg.json                # C++ dependency manifest for vcpkg.
│
├── docs/
│   └── Development/
│       └── BuildSystem.md    # This file.
│
├── src/                      # All project source code.
│   └── cpp/                  # C++ source code, organized by logical components.
│       ├── component_a/
│       └── component_b/
│
└── build/                    # Build output directory (ignored by Git).
```

---

## 2. Tools and Build Philosophy

### Primary Tool: CMake
**CMake** is the primary orchestrator for the C++ build. It manages complex C++ projects, is cross-platform, and provides the scripting capabilities necessary for robust build management.

### C++ Dependency Management: vcpkg
All external C++ libraries (e.g., GLFW, GLM, fmt) can be managed via **vcpkg** in manifest mode. A `vcpkg.json` file in the project root declares all dependencies.

### IDE and Platform Agnosticism
CMake, along with `CMakePresets.json`, ensures that the project is not tied to any specific IDE, allowing developers to use various editors on different operating systems.

---

## 3. Build Architecture: From Source to Final Artifacts

The build architecture should be designed to support both local development and the delivery of robust packages.

### 3.1. Build Phases

The compilation process typically involves:

1.  **Native Compilation (C++):** Using CMake, all core components and low-level implementations are compiled into native libraries (e.g., `.dll` on Windows, `.so` on Linux, `.dylib` on macOS).
2.  **Packaging (Optional):** Creating distributable packages for libraries or applications.

In a Continuous Integration environment, these phases are executed sequentially to ensure all tests pass before proceeding to packaging.
