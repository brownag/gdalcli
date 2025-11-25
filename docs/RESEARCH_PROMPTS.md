# Research Prompts for Future gdalcli Enhancements

This document contains detailed research prompts for three pending enhancements to the gdalcli package. These prompts are designed to guide investigation into advanced gdalraster API features and GDAL 3.12+ capabilities.

## 1. Enhance Debugging with `getExplicitlySetArgs()`

### Research Objective
Investigate how to integrate gdalraster's `getExplicitlySetArgs()` method into gdalcli for improved debugging, logging, and introspection capabilities.

### Key Questions to Answer

1. **API Functionality**
   - What does `GDALAlg$getExplicitlySetArgs()` return?
   - What is the difference between "explicitly set" arguments vs. default arguments?
   - How can this be useful for debugging user-created jobs?
   - Does it return a list, character vector, or other structure?

2. **Use Cases**
   - How could this improve error messages when GDAL commands fail?
   - Could this be used for job validation before execution?
   - Would this help users understand what they've configured?
   - Can this be used for audit logging/tracing?

3. **Integration Points**
   - Where in the execution pipeline should this be called?
   - Should this be exposed as a user-facing function or internal only?
   - How should it interact with `gdal_job_run(..., verbose=TRUE)`?
   - Could this enhance the `print.gdal_job()` method?

4. **Implementation Strategy**
   - Create `gdal_job_inspect_args()` function to show explicitly set args?
   - Add optional debug logging to `gdal_job_run_gdalraster()`?
   - Integrate with existing verbose output system?
   - Should this apply to processx and reticulate backends too?

5. **Testing & Documentation**
   - Write test cases showing before/after with explicit args
   - Document which gdalraster version required (≥2.3.0?)
   - Show practical examples of debugging complex jobs
   - Demonstrate interaction with version checking

### Research Output Format
Provide:
- Summary of `getExplicitlySetArgs()` behavior
- Use case recommendations (prioritized)
- Integration approach recommendation
- Code example showing proposed implementation
- Version compatibility table

---

## 2. Implement Vector-Specific Optimization: `setVectorArgsFromObject()`

### Research Objective
Investigate how to use gdalraster's `setVectorArgsFromObject()` to automatically configure vector operations based on GDALVector input objects, reducing boilerplate for vector workflows.

### Key Questions to Answer

1. **API Functionality**
   - What types of objects can be passed to `setVectorArgsFromObject()`?
   - What arguments are automatically extracted? (CRS, bounds, geometry type, etc.?)
   - Does it require a specific GDALVector object or compatible types?
   - What happens if the object doesn't have required metadata?

2. **Vector Workflow Benefits**
   - Which vector operations would benefit most from this?
   - Common patterns: reproject from input CRS, buffer geometry, etc.?
   - Could this reduce user code for cloud-native vector workflows?
   - Would this improve performance by avoiding redundant specifications?

3. **Integration Scenarios**
   - Pipeline pattern: `gdal_vector_info(obj) |> gdal_vector_buffer()` - auto-detect geometry type?
   - S3 method extension: `gdal_*` functions accepting GDALVector objects natively?
   - Piping improvement: Detect when input is GDALVector and auto-apply settings?
   - Should this work with both gdalraster GDALVector and sf/terra objects?

4. **Implementation Considerations**
   - Should this be opt-in (explicit function call) or automatic?
   - Compatibility with existing `extend_gdal_pipeline()` mechanism?
   - How to handle conflicts between user-provided args and auto-detected args?
   - Should priority be user args > auto-detected > defaults?

5. **Limitations & Fallbacks**
   - What happens with non-vector objects?
   - Error messages for incompatible object types?
   - Graceful degradation when metadata unavailable?
   - User control over auto-detection behavior?

### Research Output Format
Provide:
- Explanation of setVectorArgsFromObject behavior
- Supported object types and their metadata extraction
- Vector operation compatibility matrix
- Proposed implementation pattern (wrapper functions vs. S3 dispatch)
- Example workflows showing code reduction
- Performance impact assessment

---

## 3. Leverage GDALG Format Driver for GDAL 3.12+ Native Serialization

### Research Objective
Investigate how to utilize GDAL 3.12+'s native GDALG format driver for direct pipeline serialization, avoiding intermediate JSON processing and enabling new capabilities.

### Key Questions to Answer

1. **GDALG Format Driver Basics**
   - Is GDALG now a first-class GDAL format driver in 3.12+?
   - What is its identifier? (e.g., "GDALG", "GDAL_PIPELINE", "GDALG_DRIVER"?)
   - Can it be used with `gdal raster convert` to create GDALG files?
   - Does it support both reading and writing?

2. **Capabilities vs. Current Implementation**
   - How does native driver differ from current JSON serialization?
   - Does it preserve more metadata (version, options, config)?
   - Are there round-trip improvements?
   - Can it be used directly in pipelines: `gdal raster pipeline | gdal convert --output-format GDALG`?

3. **Architectural Impact**
   - Could GDALG driver replace `gdal_save_pipeline()` functionality?
   - Would this allow bidirectional conversion with GDAL Python/C++?
   - Enable interoperability with GDAL CLI tools directly?
   - Simplify caching/persistence mechanisms?

4. **New Workflow Possibilities**
   - Direct GDALG generation without intermediate JSON parsing?
   - Stream pipeline directly to GDALG format in one operation?
   - Use GDALG files as native GDAL format, not just for R persistence?
   - Enable tools like `gdalinfo pipeline.gdalg` to work natively?

5. **Version & Compatibility Strategy**
   - Minimum GDAL version for GDALG driver? (3.12.0 or later?)
   - Should this be optional feature (graceful fallback to current JSON)?
   - Detection logic: `gdal raster convert --formats | grep -i gdalg`?
   - How to test without GDAL 3.12+?

6. **Implementation Approach**
   - Add `gdal_save_pipeline_native()` using format driver?
   - Enhance `gdal_save_pipeline()` to auto-detect capability?
   - New backend for `gdal_job_run()` that uses format driver?
   - CLI integration: render pipeline directly to GDALG?

### Research Output Format
Provide:
- Overview of GDALG format driver capabilities/limitations
- Comparison table: current JSON vs. native driver approach
- Version compatibility matrix
- Integration recommendations (phased approach)
- Example implementations for key workflows
- Performance/storage comparison

---

## Research Methodology

For each topic, use the following approach:

1. **Investigation Sources**
   - gdalraster package documentation and source code
   - GDAL 3.12 release notes and API documentation
   - GDAL RFC documents related to CLI and pipelines
   - Existing gdalcli codebase patterns

2. **Testing Strategy**
   - Create minimal reproducible examples
   - Test both success and edge cases
   - Verify compatibility with current gdalcli architecture
   - Document any breaking changes or new requirements

3. **Documentation**
   - Explain discovered capabilities clearly
   - Provide working code examples
   - Identify any performance implications
   - Note version requirements explicitly

4. **Recommendations**
   - Prioritize by user impact and implementation effort
   - Suggest phased rollout strategy
   - Identify architectural improvements needed
   - Plan for backward compatibility

---

## Success Criteria

A successful research effort will produce:

- ✅ Clear understanding of each feature's capabilities
- ✅ Practical use cases with code examples
- ✅ Integration recommendations aligned with gdalcli philosophy
- ✅ Version compatibility and dependency requirements
- ✅ Implementation roadmap with effort estimates
- ✅ Documentation outline for user-facing features
- ✅ Test cases for new functionality

---

## Timeline & Priority

These investigations can be conducted in parallel. Suggested priority:

1. **High**: GDALG Format Driver (enables GDAL 3.12 native workflows)
2. **Medium**: setVectorArgsFromObject (improves vector user experience)
3. **Medium**: getExplicitlySetArgs (debugging/introspection quality-of-life)

---

## Reference Documents

- GDAL 3.12 Release Notes: https://gdal.org/development/release_notes.html
- gdalraster Documentation: https://cran.r-project.org/package=gdalraster
- Current gdalcli Implementation: See core-gdal_run.R, core-gdal-discovery.R
