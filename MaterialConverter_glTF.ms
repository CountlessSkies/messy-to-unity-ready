/*
===============================================================================
glTF Material Converter for 3ds Max
===============================================================================
Description:
    A MaxScript utility tool to convert Standard, Physical, and VRayMtl 
    materials to the native glTFMaterial in 3ds Max (v2023+).
    Optimized for glTF export to Unity/Unreal Engine.

Usage:
    1. Run script in 3ds Max (Scripting -> Run Script...)
    2. Select options (All objects or Selection only)
    3. Click "Convert Materials"
===============================================================================
*/

try(destroyDialog glTFMaterialConverterRollout)catch()

rollout glTFMaterialConverterRollout "glTF Material Converter v1.0" width:320 height:480
(
    -- UI Controls
    group "Target Mode" (
        radiobuttons rad_target "" labels:#("Selected Objects Only", "All Objects in Scene") default:1 align:#left
    )
    
    group "Material Types to Convert" (
        checkbox chk_standard "Standard Materials" checked:true
        checkbox chk_physical "Physical Materials" checked:true
        checkbox chk_vray "VRay Materials (VRayMtl)" checked:true
    )
    
    group "Options" (
        checkbox chk_rename "Suffix converted materials with '_glTF'" checked:true
        checkbox chk_normal "Convert Normal/Bump Maps" checked:true
    )
    
    button btn_convert "Convert Materials" width:280 height:40 style:#flat
    
    group "Log Output" (
        edittext edt_log "" readOnly:true height:120 labelOnTop:false
    )
    
    label lbl_info "Ready. Requires 3ds Max 2023+ for glTF Material." align:#center
    
    -- Global arrays for caching converted materials to maintain instancing
    local originalMats = #()
    local convertedMats = #()
    local logBuffer = ""
    
    -- Function to write logs to the UI log output
    fn addLog msg = (
        logBuffer += (msg as string) + "\n"
        edt_log.text = logBuffer
    )
    
    -- Helper function to convert all VRayBitmap/VRayHDRI inside a material to standard Bitmaptexture
    fn convertVRayBitmapsInMaterial mat = (
        if mat == undefined do return mat
        format "      [VRayBitmapConvert] Start for material: %\n" mat.name
        
        -- Resolve VRayBitmap class dynamically
        local vrayBitmapClass = if (globalVars.isGlobal #VRayBitmap) then (globalVars.get #VRayBitmap) else (if (globalVars.isGlobal #VRayHDRI) then (globalVars.get #VRayHDRI) else undefined)
        if vrayBitmapClass == undefined do (
            format "      [VRayBitmapConvert] VRayBitmap class not found in scene, skipping.\n"
            return mat
        )
        
        -- Use 3ds Max native C++ getClassInstances to find all instances recursively (no script recursion hang)
        local vrayMaps = getClassInstances vrayBitmapClass target:mat
        format "      [VRayBitmapConvert] Found % VRayBitmaps\n" vrayMaps.count
        for vMap in vrayMaps do (
            local filePath = ""
            if hasProperty vMap "HDRIMapName" then (
                filePath = vMap.HDRIMapName
            ) else if hasProperty vMap "filename" do (
                filePath = vMap.filename
            )
            format "      [VRayBitmapConvert] Converting map: %, file: %\n" vMap filePath
            
            if filePath != "" and filePath != undefined do (
                local newMap = Bitmaptexture filename:filePath
                
                -- Copy basic tiling/coords if applicable
                if hasProperty vMap "coords" and hasProperty newMap "coords" do (
                    newMap.coords.U_Tiling = vMap.coords.U_Tiling
                    newMap.coords.V_Tiling = vMap.coords.V_Tiling
                    newMap.coords.U_Offset = vMap.coords.U_Offset
                    newMap.coords.V_Offset = vMap.coords.V_Offset
                )
                
                -- Native C++ replaceInstances replaces it instantly everywhere under the material
                format "      [VRayBitmapConvert] Replacing instances for %\n" vMap
                replaceInstances vMap newMap
                format "      [VRayBitmapConvert] Finished replacing instances\n"
                addLog ("Converted VRayBitmap to Bitmaptexture: " + (filenameFromPath filePath))
            )
        )
        format "      [VRayBitmapConvert] Done for material: %\n" mat.name
        return mat
    )
    
    -- Helper function to invert texture using libvips via .NET Process
    fn invertTextureWithVips inputPath = (
        if inputPath == undefined or inputPath == "" do return undefined
        format "        [VipsInvert] Start for file: %\n" inputPath
        
        -- Check if source texture exists using fast .NET check to avoid 3ds Max search paths hang
        local fileIO = dotNetClass "System.IO.File"
        if not (fileIO.Exists inputPath) do (
            addLog ("Warning: Texture is missing, skipping invert: " + (filenameFromPath inputPath))
            format "        [VipsInvert] File missing, skipping.\n"
            return undefined
        )
        
        -- Resolve vips.exe path
        local scriptPath = getFilenamePath (getSourceFileName())
        if scriptPath == undefined or scriptPath == "" do (
            scriptPath = "d:\\AgentWorks\\messy-to-unity-ready\\" -- fallback workspace path
        )
        local vipsExe = scriptPath + "vips-dev-8.18\\bin\\vips.exe"
        
        if not (fileIO.Exists vipsExe) do (
            addLog ("Error: vips.exe not found at " + vipsExe)
            format "        [VipsInvert] vips.exe missing at: %\n" vipsExe
            return undefined
        )
        
        -- Prepare output file path
        local dir = getFilenamePath inputPath
        local fileBaseName = getFilenameFile inputPath
        local ext = getFilenameType inputPath
        local outputPath = dir + fileBaseName + "_roughness" + ext
        
        -- Optimize: If already inverted, return existing file
        if (fileIO.Exists outputPath) do (
            format "        [VipsInvert] Output file already exists: %, skipping process.\n" outputPath
            return outputPath
        )
        
        format "        [VipsInvert] Running CLI: % invert % %\n" vipsExe inputPath outputPath
        -- Run libvips invert using .NET Process
        try (
            local process = dotNetObject "System.Diagnostics.Process"
            process.StartInfo.FileName = vipsExe
            process.StartInfo.Arguments = "invert \"" + inputPath + "\" \"" + outputPath + "\""
            process.StartInfo.UseShellExecute = false
            process.StartInfo.CreateNoWindow = true
            process.StartInfo.RedirectStandardError = true
            
            process.Start()
            local stdErr = process.StandardError.ReadToEnd()
            
            -- Wait for exit with a 5000ms (5 seconds) timeout to prevent infinite freezes
            local exited = process.WaitForExit(5000)
            
            if not exited then (
                process.Kill()
                addLog ("Warning: Invert process timed out for " + filenameFromPath inputPath)
                format "        [VipsInvert] Process timed out, killed.\n"
                return undefined
            ) else (
                format "        [VipsInvert] Process exit code: %\n" process.ExitCode
                if process.ExitCode == 0 then (
                    addLog ("Successfully inverted texture: " + filenameFromPath outputPath)
                    return outputPath
                ) else (
                    addLog ("vips.exe error: " + stdErr)
                    return undefined
                )
            )
        ) catch (
            addLog ("Failed to run libvips process: " + (getCurrentException()))
            format "        [VipsInvert] Exception: %\n" (getCurrentException())
            return undefined
        )
    )
    
    -- Resolve the actual glTF Material Class dynamically using globalVars to avoid compiler checks
    local glTFClass = if (globalVars.isGlobal #glTFMaterial) then (globalVars.get #glTFMaterial) else (if (globalVars.isGlobal #glTF_Material) then (globalVars.get #glTF_Material) else undefined)
    
    -- Resolve standard classes to avoid missing class compile errors
    local standardClass = if (globalVars.isGlobal #Standardmaterial) then (globalVars.get #Standardmaterial) else (if (globalVars.isGlobal #StandardMaterial) then (globalVars.get #StandardMaterial) else undefined)
    local physicalClass = if (globalVars.isGlobal #PhysicalMaterial) then (globalVars.get #PhysicalMaterial) else undefined
    local vrayClass = if (globalVars.isGlobal #VRayMtl) then (globalVars.get #VRayMtl) else undefined
    
    -- Main Conversion Logic per Material
    fn convertSingleMaterial mat = (
        if mat == undefined do return undefined
        
        -- 1. Check if it's already a glTF material (Fast check)
        local matClass = classOf mat
        if matClass == glTFClass do (
            if not chk_normal.checked and mat.normalMap != undefined do (
                mat.normalMap = undefined
                addLog ("Removed Normal Map from existing glTF Material: " + mat.name)
            )
            return mat
        )
        
        -- 2. Look up cache to preserve instancing (Fast check)
        local idx = findItem originalMats mat
        if idx > 0 do return convertedMats[idx]
        
        format "--> Entering convertSingleMaterial for: %, class: %\n" mat.name matClass
        
        -- 3. Convert any VRayBitmap inside the material to standard Bitmaptexture
        format "    Running convertVRayBitmapsInMaterial for: %\n" mat.name
        mat = convertVRayBitmapsInMaterial mat
        format "    Finished convertVRayBitmapsInMaterial for: %\n" mat.name
        
        -- Update class after potential map conversion
        matClass = classOf mat
        
        -- Recheck cache after potential VRayBitmap conversion modifications
        local idx2 = findItem originalMats mat
        if idx2 > 0 do (
            format "<-- Material found in cache (after map conversion), returning: %\n" convertedMats[idx2].name
            return convertedMats[idx2]
        )
        
        local newMat
        
        -- Handle Multi/Sub-Object Material
        if matClass == MultiMaterial do (
            format "    Processing MultiMaterial: %, numsubs: %\n" mat.name mat.numsubs
            newMat = MultiMaterial name:(mat.name + (if chk_rename.checked then "_glTF" else "")) numsubs:mat.numsubs
            -- Cache it immediately to handle circular references or sub-material instances
            append originalMats mat
            append convertedMats newMat
            
            for i = 1 to mat.numsubs do (
                if mat[i] != undefined then (
                    format "    Converting sub-material %/%: %\n" i mat.numsubs mat[i].name
                    newMat[i] = convertSingleMaterial mat[i]
                    if mat.names[i] != undefined and mat.names[i] != "" do (
                        newMat.names[i] = mat.names[i] as string
                    )
                ) else (
                    format "    Sub-material %/% is undefined\n" i mat.numsubs
                )
            )
            format "<-- Finished MultiMaterial: %\n" mat.name
            return newMat
        )
        
        -- Setup Conversion Target glTF Material
        local targetName = mat.name + (if chk_rename.checked then "_glTF" else "")
        local converted = false
        
        -- 1. Standard Material
        if (matClass == standardClass) and chk_standard.checked then (
            newMat = glTFClass name:targetName
            converted = true
            
            -- Base Color & Map
            newMat.baseColor = mat.diffuse
            if mat.diffuseMap != undefined do (
                newMat.baseColorMap = mat.diffuseMap
            )
            
            -- Roughness approximation (1.0 - glossiness)
            if mat.glossinessMap != undefined then (
                newMat.roughness = 1.0 -- Full strength for map
                if classOf mat.glossinessMap == Bitmaptexture and mat.glossinessMap.filename != "" then (
                    local invertedPath = invertTextureWithVips mat.glossinessMap.filename
                    if invertedPath != undefined then (
                        newMat.roughnessMap = Bitmaptexture filename:invertedPath
                    ) else (
                        newMat.roughnessMap = mat.glossinessMap
                    )
                ) else (
                    newMat.roughnessMap = mat.glossinessMap
                )
            ) else (
                newMat.roughness = 1.0 - (mat.glossiness / 100.0)
            )
            
            -- Bump/Normal Map
            if chk_normal.checked and mat.bumpMap != undefined do (
                newMat.normalMap = mat.bumpMap
            )
            
            -- Opacity
            if mat.opacityMap != undefined do (
                newMat.alphaMode = 1 -- Mask/Blend mode
            )
            
            -- Self-illumination (Emission)
            if mat.selfIllumMap != undefined then (
                newMat.emissionMap = mat.selfIllumMap
            ) else (
                if mat.useSelfIllumColor then (
                    newMat.emissionColor = mat.selfIllumColor
                ) else if mat.selfIllumAmount > 0.0 do (
                    newMat.emissionColor = mat.diffuse * (mat.selfIllumAmount / 100.0)
                )
            )
            
            addLog ("Converted Standard Material: " + mat.name)
        )
        
        -- 2. Physical Material
        else if (physicalClass != undefined and matClass == physicalClass) and chk_physical.checked then (
            newMat = glTFClass name:targetName
            converted = true
            
            -- Base Color & Map
            newMat.baseColor = mat.base_color
            if mat.base_color_map != undefined do (
                newMat.baseColorMap = mat.base_color_map
            )
            
            -- Roughness
            if mat.roughness_map != undefined then (
                newMat.roughness = 1.0 -- Full strength for map
                if mat.roughness_inv == true then (
                    -- Glossiness mode (needs inversion)
                    if classOf mat.roughness_map == Bitmaptexture and mat.roughness_map.filename != "" then (
                        local invertedPath = invertTextureWithVips mat.roughness_map.filename
                        if invertedPath != undefined then (
                            newMat.roughnessMap = Bitmaptexture filename:invertedPath
                        ) else (
                            newMat.roughnessMap = mat.roughness_map
                        )
                    ) else (
                        newMat.roughnessMap = mat.roughness_map
                    )
                ) else (
                    newMat.roughnessMap = mat.roughness_map
                )
            ) else (
                -- Physical Material supports both Roughness and Glossiness mode
                if mat.roughness_inv == true then (
                    -- Glossiness mode (needs inversion)
                    newMat.roughness = 1.0 - mat.roughness
                ) else (
                    newMat.roughness = mat.roughness
                )
            )
            
            -- Metalness
            newMat.metalness = mat.metalness
            if mat.metalness_map != undefined do (
                newMat.metalnessMap = mat.metalness_map
            )
            
            -- Bump/Normal Map
            if chk_normal.checked and mat.bump_map != undefined do (
                newMat.normalMap = mat.bump_map
            )
            
            -- Emission
            if mat.emit_color_map != undefined then (
                newMat.emissionMap = mat.emit_color_map
            ) else (
                newMat.emissionColor = mat.emit_color * (mat.emission / 1.0) -- scale by luminance/intensity
            )
            
            addLog ("Converted Physical Material: " + mat.name)
        )
        
        -- 3. VRay Material (VRayMtl)
        else if (vrayClass != undefined and matClass == vrayClass) and chk_vray.checked then (
            newMat = glTFClass name:targetName
            converted = true
            
            -- Base Color & Map
            newMat.baseColor = mat.diffuse
            if mat.texmap_diffuse != undefined do (
                newMat.baseColorMap = mat.texmap_diffuse
            )
            
            -- Metalness
            if hasProperty mat "reflection_metalness" do (
                newMat.metalness = mat.reflection_metalness
            )
            if hasProperty mat "texmap_metalness" and mat.texmap_metalness != undefined do (
                newMat.metalnessMap = mat.texmap_metalness
            )
            
            -- Roughness / Glossiness
            local isRoughness = false
            if hasProperty mat "brdf_useRoughness" do (
                isRoughness = mat.brdf_useRoughness == true
            )
            
            if mat.texmap_reflectionGlossiness != undefined then (
                newMat.roughness = 1.0 -- Full strength for map
                if isRoughness then (
                    newMat.roughnessMap = mat.texmap_reflectionGlossiness
                ) else (
                    -- Default VRayMtl is Glossiness mode (needs inversion)
                    if classOf mat.texmap_reflectionGlossiness == Bitmaptexture and mat.texmap_reflectionGlossiness.filename != "" then (
                        local invertedPath = invertTextureWithVips mat.texmap_reflectionGlossiness.filename
                        if invertedPath != undefined then (
                            newMat.roughnessMap = Bitmaptexture filename:invertedPath
                        ) else (
                            newMat.roughnessMap = mat.texmap_reflectionGlossiness
                        )
                    ) else (
                        newMat.roughnessMap = mat.texmap_reflectionGlossiness
                    )
                )
            ) else (
                -- No texture case: calculate value based on mode
                if isRoughness then (
                    newMat.roughness = mat.reflection_glossiness
                ) else (
                    newMat.roughness = 1.0 - mat.reflection_glossiness
                )
            )
            
            -- Bump / Normal Map
            if chk_normal.checked and mat.texmap_bump != undefined do (
                newMat.normalMap = mat.texmap_bump
            )
            
            -- Self-illumination
            if hasProperty mat "texmap_self_illumination" and mat.texmap_self_illumination != undefined then (
                newMat.emissionMap = mat.texmap_self_illumination
            ) else if hasProperty mat "selfIllumination" then (
                newMat.emissionColor = mat.selfIllumination
            )
            
            addLog ("Converted VRayMtl Material: " + mat.name)
        )
        
        -- If conversion succeeded, cache and return new material
        if converted then (
            append originalMats mat
            append convertedMats newMat
            return newMat
        ) else (
            -- Keep original if not supported/checked
            return mat
        )
    )
    
    -- Main Run Handler
    on btn_convert pressed do (
        logBuffer = ""
        edt_log.text = ""
        originalMats = #()
        convertedMats = #()
        
        -- Verify that glTF class is actually available in this 3ds Max version
        if (glTFClass == undefined) do (
            messageBox "glTFMaterial / glTF_Material class is not available. Please make sure you are running 3ds Max 2023 or newer." title:"Error"
            return false
        )
        
        -- Close Material Editor to prevent UI redraw freezes (especially with Slate Material Editor)
        local meWasOpen = MatEditor.isOpen()
        if meWasOpen do MatEditor.Close()
        
        addLog "Starting material conversion..."
        
        -- Select targets
        local targetNodes = #()
        if rad_target.state == 1 then (
            targetNodes = selection as array
            if targetNodes.count == 0 do (
                messageBox "Please select at least one object." title:"No Selection"
                return false
            )
        ) else (
            targetNodes = objects as array
        )
        
        local convertCount = 0
        
        -- Process nodes
        undo "Convert materials to glTF" on (
            for n in targetNodes do (
                if n.material != undefined do (
                    format "=== Start node: % ===\n" n.name
                    local convertedMat = convertSingleMaterial n.material
                    if convertedMat != n.material do (
                        n.material = convertedMat
                        convertCount += 1
                    )
                    format "=== End node: % ===\n" n.name
                )
                -- Force Windows to process pending window messages (prevents UI freeze/ghosting)
                windows.processPostedMessages()
            )
        )
        
        addLog ("Conversion complete! Processed " + convertCount as string + " objects.")
        
        -- Reopen Material Editor if it was open originally
        if meWasOpen do MatEditor.Open()
    )
)

-- Open UI window
createDialog glTFMaterialConverterRollout
