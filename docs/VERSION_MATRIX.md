# gdalcli Version Compatibility Matrix

This document defines feature availability and compatibility across GDAL and R versions.

## GDAL Version Support Strategy

`gdalcli` follows semantic versioning aligned with GDAL minor versions:
- **Minor version release per GDAL update** (e.g., 0.3.x for GDAL 3.12 support)
- **Patch versions** for bug fixes and non-breaking improvements
- **Backward compatibility** maintained for previous GDAL versions

## Core Features by GDAL Version

| Feature | GDAL 3.11 | GDAL 3.12+ | Status | Notes |
|---------|-----------|-----------|--------|-------|
| CLI Framework | Yes | Yes | Stable | Unified CLI available since GDAL 3.11 |
| 80+ Algorithm Functions | Yes | Yes + 9 new | Stable | Auto-generated from gdal --json-usage |
| Native Pipeline Execution | Yes | Yes | Stable | gdal raster/vector pipeline commands |
| GDALG Format (JSON) | Yes | Yes | Stable | Custom yyjsonr-based serialization |
| GDALG Format Driver | No | Yes | New | Use gdal ... --output-format GDALG |
| Shell Script Rendering | Yes | Yes | Stable | bash/zsh script export |
| Configuration Options | Yes | Yes | Stable | Full GDAL config support |
| VSI Streaming | Yes | Yes | Stable | /vsistdin/, /vsistdout/, cloud storage |

## Backend Support

All three execution backends support the same feature set:

| Backend | Min Version | Status | Performance | Use Case |
|---------|-------------|--------|-------------|----------|
| **processx** (default) | R 4.1 | Stable | Good | General purpose, pure R |
| **gdalraster** | gdalraster 2.2.0 | Stable | Excellent | C++ bindings, advanced features |
| **reticulate** | Python 3.6+ | Experimental | Good | Python GDAL integration |

## New Algorithms by GDAL Version

### GDAL 3.11 Base Algorithms

**Raster (29 operations):**
- aspect, calc, clean-collar, clip, color-map, contour, convert, create, edit
- fill-nodata, footprint, hillshade, index, info, mosaic, overview (add/delete)
- pixel-info, polygonize, reclassify, reproject, resize, roughness, scale
- select, set-type, sieve, slope, stack, tile, tpi, tri, unscale, viewshed

**Vector (24 operations):**
- clip, concat, convert, edit, filter, geom (buffer, explode-collections, make-valid, segmentize, set-type, simplify, swap-xy)
- grid (average, average-distance, average-distance-points, count, invdist, invdistnn, linear, maximum, minimum, nearest, range)
- info, pipeline, rasterize, reproject, select, sql

**Multidimensional (2 operations):**
- convert, info

### GDAL 3.12 New Algorithms

**Raster (9 new operations):**
- `raster blend` - Blend multiple rasters
- `raster compare` - Compare rasters for differences
- `raster neighbors` - Analyze pixel neighborhoods
- `raster nodata-to-alpha` - Convert nodata to alpha channel
- `raster pansharpen` - Pansharpening
- `raster proximity` - Compute proximity/distance maps
- `raster rgb-to-palette` - RGB to palette conversion
- `raster update` - Update raster in-place
- `raster zonal-stats` - Zonal statistics
- `raster as-features` - Convert raster to vector features

**Vector (5 new operations):**
- `vector check-coverage` - Validate vector coverage
- `vector check-geometry` - Geometry validation
- `vector clean-coverage` - Clean overlapping coverage
- `vector index` - Create spatial index
- `vector layer-algebra` - Spatial algebra operations (union, intersection, etc.)
- `vector make-point` - Create points from coordinates
- `vector partition` - Partition vector dataset
- `vector set-field-type` - Change field data types
- `vector simplify-coverage` - Topology-aware simplification

## R Package Version Matrix

| gdalcli | Release Date | GDAL | R Min | Key Features |
|---------|--------------|------|-------|--------------|
| 0.1.x | Sept 2024 | 3.11 | 4.1 | Initial release |
| 0.2.x | Nov 2024 | 3.11 | 4.1 | JSON output, backends, discovery |
| **0.3.x** | *TBD* | 3.12 | 4.1 | Format driver, new algorithms |
| **0.4.x** | *TBD* | 3.12 | 4.1 | Advanced features (setArg, etc.) |

## Dependency Version Matrix

| Dependency | Minimum | Recommended | Status | Notes |
|------------|---------|------------|--------|-------|
| R | 4.1 | Latest | Stable | - |
| GDAL | 3.11.3 | Latest | Stable | System requirement |
| processx | 3.8.0 | Latest | Stable | Default backend |
| yyjsonr | 0.1.0 | Latest | Stable | JSON processing |
| rlang | 1.0.0 | Latest | Stable | Error handling |
| cli | 3.0.0 | Latest | Stable | User messages |
| digest | 0.6.0 | Latest | Stable | Caching |
| gdalraster | 2.2.0 | 2.3.0+ | Optional | Advanced backend |
| reticulate | 1.28 | Latest | Optional | Python backend |
| knitr | - | Latest | Build-time | Documentation |
| rmarkdown | - | Latest | Build-time | Documentation |
| testthat | 3.0.0 | Latest | Test-time | Unit tests |

## Feature Availability by Release

### 0.1.x (GDAL 3.11 Foundation)

[yes] 80+ auto-generated algorithm functions
[yes] Lazy evaluation framework
[yes] Pipe-aware job composition
[yes] Native pipeline execution
[yes] GDALG JSON format persistence
[yes] Shell script generation
[yes] processx backend
[yes] Configuration options
[yes] VSI streaming support
[no] Advanced debugging (getExplicitlySetArgs)
[no] Vector optimization (setVectorArgsFromObject)
[no] GDALG format driver

### 0.2.x (Enhanced Execution)

[yes] All 0.1.x features
[yes] gdalraster backend (C++ bindings)
[yes] reticulate backend (Python)
[yes] JSON output streaming (stream_out_format=json)
[yes] Discovery utilities (gdal_list_commands, gdal_command_help, gdal_check_version)
[yes] Enhanced error messages
[yes] Backend selection guide
[yes] Version compatibility documentation
[no] GDAL 3.12 algorithms
[no] GDALG format driver

### 0.3.x (GDAL 3.12+ Integration)

[yes] All 0.2.x features
[yes] 9 new GDAL raster algorithms (blend, proximity, zonal-stats, etc.)
[yes] 5 new GDAL vector algorithms (layer-algebra, simplify-coverage, etc.)
[yes] GDALG format driver support
[yes] Version-conditional algorithm exposure
[yes] GDAL 3.12 feature detection
[yes] Performance improvements from native GDALG
[no] getExplicitlySetArgs integration
[no] setVectorArgsFromObject integration

### 0.4.x (Advanced Features)

[yes] All 0.3.x features
[yes] getExplicitlySetArgs() for debugging
[yes] setVectorArgsFromObject() for vector workflows
[yes] Advanced job introspection
[yes] gdalraster 2.3.0+ integration
[yes] Performance optimizations

## Testing & Validation Matrix

| Component | GDAL 3.11 | GDAL 3.12 | GDR 2.2 | GDR 2.3 | Reticulate |
|-----------|-----------|-----------|---------|---------|-----------|
| CLI discovery | yes | yes | yes | yes | yes |
| Algorithm generation | yes | yes | yes | yes | yes |
| Lazy evaluation | yes | yes | yes | yes | yes |
| Native pipelines | yes | yes | yes | yes | yes |
| GDALG persistence | yes | yes | yes | yes | yes |
| JSON streaming | yes | yes | yes | yes | yes |
| processx backend | yes | yes | yes | yes | yes |
| gdalraster backend | no | yes | yes | yes | no |
| Format driver | no | yes | no | yes | no |
| Advanced features | no | no | no | yes | no |

(GDR = gdalraster, N/A = feature not applicable to this version)

## Deprecation Policy

### Version 0.2.x
- No deprecations

### Version 0.3.x
- No deprecations planned

### Future Versions
- Deprecation period: minimum 2 minor version releases before removal
- Clear warnings in function documentation
- Migration guide provided

## Upgrade Path

```
0.1.x → 0.2.x: Drop-in replacement (same API, more backends)
0.2.x → 0.3.x: Drop-in replacement (new algorithms, optional features)
0.3.x → 0.4.x: Drop-in replacement (advanced features optional)
```

All updates maintain backward compatibility with existing code.

## Version Detection at Runtime

```r
# Check GDAL version
gdal_check_version("3.11")  # TRUE if >= 3.11
gdal_check_version("3.12")  # TRUE if >= 3.12

# List algorithms for installed GDAL
gdal_list_commands()  # Shows exactly what's available

# Get help for a command
gdal_command_help("raster.info")  # Works on any version
```

## Tagged Release Strategy

### Release Schedule
- **Minor version bumps** aligned with GDAL releases
- **Patch versions** for maintenance
- **Release candidate tags** (e.g., v0.3.0-rc1) for testing

### Tagging Convention
```
v0.2.0          - GDAL 3.11 stable release
v0.2.1          - Bug fix
v0.3.0-rc1      - GDAL 3.12 release candidate
v0.3.0          - GDAL 3.12 stable release
v0.3.1          - GDAL 3.12 maintenance
v0.4.0          - Advanced features for GDAL 3.12+
```

### Archive Maintenance
- Keep all releases available
- Provide branch for each GDAL major version
- Documentation versioning for each release
