// Binding-generation input only — NOT engine API.
// Pulls every asset-domain header into a single translation unit so
// ClangSharp's --traverse can emit them. The C kernel API has no such
// umbrella; this file lives beside Asset.rsp and is consumed only by it.
#pragma once
#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/asset/mesh_shape.h>
#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/asset/asset_loader.h>
#include <kernel_engine/asset/asset_resolver.h>
