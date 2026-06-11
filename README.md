# glTF Material Converter for 3ds Max

A high-performance MaxScript utility tool to convert Standard, Physical, and VRayMtl materials to native **glTFMaterial** in 3ds Max (v2023+). Highly optimized for assets prep before exporting to Unity or Unreal Engine.

---

## Key Features

- **VRayBitmap to Bitmaptexture Conversion**: Recursively finds and converts all V-Ray custom texture loaders (`VRayBitmap`/`VRayHDRI`) to standard 3ds Max `Bitmaptexture` maps.
- **Auto Glossiness to Roughness Inversion**: Automatically inverts Glossiness texture maps to Roughness maps using the high-performance **libvips** library (pre-packaged in the repository).
- **Anti-Freeze & Performance Optimizations**:
  - Uses native 3ds Max C++ APIs (`getClassInstances` & `replaceInstances`) to prevent infinite recursion and stack overflows on complex nested Multi/Sub-Object materials.
  - Uses fast .NET checks (`System.IO.File.Exists`) to check for missing textures without locking the 3ds Max UI during asset path searches.
  - Keeps 3ds Max UI responsive during conversion using `windows.processPostedMessages()`.
  - Automatically temporarily closes the Material Editor (SME) during processing to prevent UI redraw loops.
- **Robust Multi/Sub-Object Material Handling**: Gracefully handles undefined sub-slots, missing sub-material names, and duplicate material references.
- **Undo Support**: Fully undoable (`Ctrl + Z`) in 3ds Max.
- **Options**:
  - Suffix converted materials with `_glTF`.
  - Convert or completely strip/exclude Normal/Bump maps from converted or existing glTF materials.

---

## Installation & Setup

This repository is **plug-and-play** (self-contained). It already includes the `vips-dev-8.18` binaries inside the project folder.

1. Clone or download this repository.
2. In 3ds Max, go to **Scripting** -> **Run Script...**
3. Locate and select **`MaterialConverter_glTF.ms`**.

---

## Usage Guide

1. **Target Mode**:
   - **Selected Objects Only**: Converts materials only on the selected nodes.
   - **All Objects in Scene**: Converts all materials in the entire active scene.
2. **Material Types to Convert**: Select which material types you wish to target (Standard, Physical, VRayMtl).
3. **Options**:
   - **Suffix converted materials with '_glTF'**: Appends a suffix to the new material names for easy sorting.
   - **Convert Normal/Bump Maps**: Uncheck this option if you want to completely strip/exclude normal maps from the converted materials, or clean up normal maps from already existing glTF materials.
4. Click **Convert Materials** to run the tool. Check the **Log Output** panel or open the **MaxScript Listener (F11)** for detailed processing steps.

---

## Requirements

- **3ds Max 2023 or newer** (for native glTFMaterial support).
- Windows OS (due to .NET integration and pre-packaged Windows `libvips` binaries).

---

# Bộ Chuyển Đổi Chất Liệu glTF cho 3ds Max (Vietnamese Summary)

Công cụ MaxScript hỗ trợ chuyển đổi tự động các chất liệu Standard, Physical, và VRayMtl sang chất liệu chuẩn **glTFMaterial** gốc của 3ds Max (v2023+). Phù hợp tối ưu hóa mô hình 3D trước khi xuất sang các Engine như Unity/Unreal.

### Điểm nổi bật:
- Tự động đổi **VRayBitmap/VRayHDRI** thành **Bitmaptexture** tiêu chuẩn.
- Tự động đảo ngược ảnh Glossiness sang Roughness bằng công cụ **libvips** siêu tốc đi kèm.
- Không lo bị treo đơ giao diện 3ds Max nhờ sử dụng gọi lệnh .NET và thuật toán C++ Native (`getClassInstances`/`replaceInstances`).
- Hỗ trợ loại bỏ Normal/Bump map hàng loạt nếu không có nhu cầu sử dụng.
- Hoạt động an toàn trên các cấu trúc vật liệu Multi/Sub-Object phức tạp.
- Hỗ trợ hoàn tác (Undo) hoàn toàn.
