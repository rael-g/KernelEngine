# Project-agnostic engineering guidelines

This document defines **project-level technical standards**.

---

## Guiding principles

* Consistency beats cleverness
* Explicit is better than implicit
* Readability and predictability outweigh brevity
* Code is written for other engineers first, compilers second

If a choice exists between two valid approaches, the one that reduces ambiguity and variation MUST be preferred.

---

## C++ and C guidelines (strict)

### Namespaces (C++)
* All code MUST live inside a project-specific root namespace followed by a domain-based structure.
* Standard pattern: `kernel_engine::domain::<subdomain>?::<name>`.
* Namespaces MUST reflect the logical domain boundaries, which in turn SHOULD align with the physical directory structure.
* `using namespace` is strictly FORBIDDEN.
* `using` declarations for specific types are RECOMMENDED in `.cc` files to shorten fully qualified names. They MUST be placed at the top of the file, BEFORE the namespace block.
* `using` declarations are FORBIDDEN in header files (`.hh`).

### File Naming and Extensions
* Files MUST use `snake_case`.
* C++ Headers: `.hh`
* C++ Implementation: `.cc`
* C Headers: `.h`
* C Implementation: `.c`
* Header/Source pairs MUST match the primary type name they implement (but in snake_case).

### Header Placement (Public vs. Private)
* **Public Headers (API):** Define the interface between components. They MUST reside in a dedicated `include/` subdirectory.
* **Private Headers (Implementation):** Contain details used only by the implementation. They MUST reside in the same directory as the `.cc` files and be included using relative paths. Private headers MUST NOT be included by other components.
* All headers MUST use `#pragma once`.

### Naming Conventions
* **C++**: Strictly follows the **Google C++ Style Guide** (PascalCase for types, etc.), but using `snake_case` for filenames.
* **C Puro**: Follows **Unix-like** conventions (snake_case for functions, types, and variables).

### Build System & CMake
* CMake logic MUST be deterministic and explicit.
* Every module MUST define its own target, preferably prefixed (e.g., `ke_`).
* Targets SHOULD be exposed using CMake aliases with the `::` operator.
* Components exposing a stable C API MUST define it in separate files (`*_api.h`, `*_api.cc`).

### Formatting
* C++ code formatting adheres to the **Microsoft C++ style** for indentation and braces (as defined in `.clang-format`).
* **Clang Tidy**: Use with caution. Do not apply automatic fixes that change logic or break established Unix-like C patterns.

---

## Memory and ownership
* Ownership MUST be explicit.
* Use the provided Engine Allocators (Malloc, Arena, Pool) for all service-level allocations to ensure telemetry and safety (Canaries).
* Raw pointers represent non-owning references unless documented otherwise.

---

## Comments
* Comments explain **why**, not **what**.
* Comments MUST NOT narrate changes or restate code.
