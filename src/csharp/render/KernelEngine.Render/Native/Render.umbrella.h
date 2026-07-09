// Binding-generation input only — NOT engine API.
// Pulls every render-domain header into a single translation unit so
// ClangSharp's --traverse can emit them. The C kernel API has no such
// umbrella; this file lives beside Render.rsp and is consumed only by it.
#pragma once
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/mesh.h>
#include <kernel_engine/render/material_file.h>
#include <kernel_engine/render/components.h>
