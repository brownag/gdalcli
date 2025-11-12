# Dynamic GDAL API Implementation Plan

## Executive Summary

This document outlines the complete implementation of a dynamic, version-aware GDAL API for the gdalcli package. The implementation follows the architectural research report and transforms gdalcli from a static API generator to a runtime-adaptive system that mirrors the Python `gdal.alg` module.

**Key Features:**
- Dynamic API generation at runtime from GDAL 3.11+ installations
- R6-based nested object structure (e.g., `gdal$raster$convert`)
- Automatic IDE autocompletion with custom S3 methods
- Full integration with existing `gdal_job` lazy evaluation system
- Version-aware caching for fast package loads
- Graceful fallback to processx backend
- Distribution via R-Universe (not CRAN)

---

## Part 1: Package Setup and Dependencies

### Step 1.1: Update DESCRIPTION File

**Files to modify:** `DESCRIPTION`

**Changes:**
- Add `gdalraster (>= 2.2.0)` and `R6 (>= 2.5.0)` to Imports
- Update Description field to mention dynamic API
- SystemRequirements already correct: `GDAL (>= 3.11)`

**Expected outcome:** Package has all required dependencies declared

---

### Step 1.2: Update NAMESPACE

**Files to modify:** `NAMESPACE` (via roxygen2 directives)

**Changes:**
- Export the `gdal` object (will be created in .onLoad)
- Export S3 methods: `.DollarNames.GdalApi` and `.DollarNames.GdalApiSub`

**Expected outcome:** roxygen2-managed exports are correct

---

## Part 2: Core R6 Class Definitions

### Step 2.1: Create `R/core-gdal-api-classes.R`

**Purpose:** Define the R6 classes that form the dynamic API structure

**Key components:**
- `GdalApi` class: Top-level object (the `gdal` instance)
- `GdalApiSub` class: Intermediate nodes (e.g., `gdal$raster`)
- Private method `build_api_structure()`: Recursively builds nested tree
- Private method `create_gdal_function()`: Factory for leaf functions

**Expected outcome:** R6 classes ready for instantiation

---

### Step 2.2: Create `R/aaa-dollar-names.R`

**Purpose:** Implement IDE autocompletion via S3 methods

**Key components:**
- `.DollarNames.GdalApi()`: Returns available top-level commands
- `.DollarNames.GdalApiSub()`: Returns available sub-commands
- Both methods avoid `NextMethod()` to bypass RStudio bug

**Expected outcome:** Tab-completion works in all IDEs

---

## Part 3: The `.onLoad` Caching Engine

### Step 3.1: Create `R/zzz.R`

**Purpose:** Package load hook with version-aware caching

**Key components:**
- Dependency check: Verify gdalraster is available
- Version check: Ensure GDAL >= 3.11
- Cache path: `tools::R_user_dir("gdalcli", "cache")`
- Cache validation: Check if cached version matches current version
- Cache miss: Build fresh API and save to cache
- Cache hit: Load pre-built API from RDS file
- Assign to namespace: Make `gdal` object available

**Expected outcome:**
- First load: Builds API, shows progress message
- Subsequent loads: Instant, silent load from cache
- Version change: Automatically rebuilds cache

---

## Part 4: The `gdal_usage()` Parser

### Step 4.1: Create `R/core-gdal-usage-parser.R`

**Purpose:** Parse GDAL help text into structured function signatures

**Key functions:**
1. `parse_gdal_usage(cmd_string)`: Main entry point
   - Calls `gdalraster::gdal_usage()` to get help text
   - Delegates to `extract_arguments_from_usage()`
   - Returns list with `formals` (alist) and `arg_info` (data.frame)

2. `extract_arguments_from_usage(usage_text)`: Regex-based parser
   - Finds Usage section in help text
   - Identifies positional arguments: `<input>`, `<output>`
   - Identifies optional flags: `-co`, `--config`
   - Extracts argument names, types, defaults
   - Returns data.frame with parsed information

3. `create_alist_from_parsed(parsed_args)`: Converts to alist
   - Creates formal argument list for `rlang::new_function()`
   - Required args have no default
   - Optional args get NULL or FALSE default
   - Always appends `...` as safety valve

**Expected outcome:** Parsed argument specifications for each GDAL command

---

## Part 5: The Function Factory

### Step 5.1: Create `R/core-gdal-function-factory.R`

**Purpose:** Metaprogramming to create user-facing functions

**Key function:**
- `create_function_from_signature(cmd_string, parsed_sig)`: Main factory

**Logic:**
1. Extract formals from `parsed_sig$formals`
2. Build function body that:
   - Captures arguments via `match.call()`
   - Handles `...` specially
   - Creates `gdal_job` object via `new_gdal_job()`
3. Use `rlang::new_function()` to create function
4. Set attributes for introspection

**Expected outcome:** Dynamically created functions ready for assignment to R6 object

---

## Part 6: Autocompletion Implementation

### Step 6.1: File Created in Step 2.2

**Already covered:** `R/aaa-dollar-names.R`

---

## Part 7: Integration with Existing gdal_run

### Step 7.1: Update `R/core-gdal_run.R`

**Purpose:** Add gdalraster backend support to `gdal_run()`

**Changes:**
- Add new S3 method: `gdal_run.gdal_job_gdalraster()`
- Extract command and arguments from gdal_job
- Set environment variables temporarily
- Call `gdalraster::gdal_run()`

**Expected outcome:** Dynamic API functions can execute via both backends

---

## Part 8: Testing Infrastructure

### Step 8.1: Create `tests/testthat/test-dynamic-api.R`

**Test cases:**
1. GdalApi class instantiation
2. Dynamic API structure validation
3. Function return types (gdal_job)
4. Autocompletion method functionality
5. Cache mechanism validation
6. Version detection and caching
7. Integration with gdal_job workflow

**Expected outcome:** Comprehensive test coverage for dynamic API

---

## Part 9: Documentation

### Step 9.1: Create `vignettes/dynamic-api.Rmd`

**Content:**
- Overview of dynamic API concept
- Comparison with static approaches
- Usage examples with autocompletion
- Backend selection (gdalraster vs processx)
- Troubleshooting guide

**Expected outcome:** User-facing documentation for dynamic API

---

### Step 9.2: Update Main Files

**Files to update:**
- `README.md`: Add section on dynamic API
- `build/README.md`: Add note about dynamic vs static generation
- DESCRIPTION: Update to mention dynamic API

**Expected outcome:** Clear communication of package's new capabilities

---

## Implementation Timeline

### Phase 1: Foundation (Steps 1-2) - ~1 hour
1. Update DESCRIPTION and NAMESPACE
2. Create R6 class definitions
3. Create autocompletion S3 methods

### Phase 2: Core Logic (Steps 3-5) - ~2 hours
4. Implement .onLoad caching engine
5. Create gdal_usage() parser
6. Create function factory

### Phase 3: Integration (Steps 6-7) - ~1 hour
7. Finalize autocompletion
8. Add gdalraster backend to gdal_run

### Phase 4: Testing & Docs (Steps 8-9) - ~1-2 hours
9. Create comprehensive tests
10. Write documentation and vignettes
11. Update README and supporting docs

### Total: ~5-6 hours

---

## File Checklist

**New files to create:**
- [ ] `R/core-gdal-api-classes.R` - R6 class definitions
- [ ] `R/core-gdal-usage-parser.R` - GDAL help text parser
- [ ] `R/core-gdal-function-factory.R` - Function metaprogramming
- [ ] `R/aaa-dollar-names.R` - S3 autocompletion methods
- [ ] `R/zzz.R` - Package load hook with caching
- [ ] `tests/testthat/test-dynamic-api.R` - Unit tests
- [ ] `vignettes/dynamic-api.Rmd` - User documentation

**Files to update:**
- [ ] `DESCRIPTION` - Add dependencies
- [ ] `R/core-gdal_run.R` - Add gdalraster backend
- [ ] `README.md` - Document dynamic API
- [ ] `NAMESPACE` (via roxygen2) - Export new items
- [ ] `build/README.md` - Note about dynamic generation

---

## Success Criteria

Upon completion, the implementation should satisfy:

1. **Dynamic API Access**
   - ✅ `gdal$raster$convert(...)` syntax works
   - ✅ `gdal$vector$info(...)` syntax works
   - ✅ All commands from `gdalraster::gdal_commands()` accessible

2. **Lazy Evaluation**
   - ✅ Functions return `gdal_job` objects
   - ✅ Jobs integrate with existing modifiers (`gdal_with_co`, etc.)
   - ✅ Jobs execute via `gdal_run()` with both backends

3. **Developer Experience**
   - ✅ IDE autocompletion works in RStudio, VSCode, Emacs
   - ✅ Function signatures show all arguments
   - ✅ Help text available for each function

4. **Performance**
   - ✅ First load: ~5-10 seconds (building API)
   - ✅ Subsequent loads: < 100ms (from cache)
   - ✅ Cache invalidates automatically on GDAL version change

5. **Backward Compatibility**
   - ✅ Existing static API functions still work
   - ✅ `gdal_run()` works with both backends
   - ✅ All existing modifiers work with dynamic jobs

6. **Distribution**
   - ✅ Clear messaging about R-Universe distribution
   - ✅ Documentation explains version-dependent API
   - ✅ Graceful degradation if gdalraster unavailable

---

## Known Limitations and Future Work

1. **Parser Limitations**
   - Current regex-based parser handles ~80% of cases
   - Complex argument patterns may need manual refinement
   - Future: Consider more sophisticated parsing (tree-based)

2. **Autocompletion Scope**
   - Works for main commands (e.g., `gdal$raster`)
   - Works for sub-commands (e.g., `convert`)
   - Argument autocompletion depends on full named signatures

3. **GDAL Version Support**
   - Requires GDAL >= 3.11
   - Gracefully degrades if unavailable
   - Future: Support older GDAL via fallback

4. **Performance Optimization**
   - Cache directory can grow (~1-2 MB per GDAL version)
   - Future: Implement cache cleanup/rotation
   - Future: Consider binary serialization formats (protobuf)

5. **Documentation Generation**
   - Currently uses help text from GDAL
   - Future: Web-scrape GDAL.org for richer documentation
   - Future: Generate roxygen2 .Rd files for each dynamic function

---

## References

- **Research Report:** `docs/architectural_research.md`
- **GDAL Unified CLI:** https://gdal.org/programs/index.html
- **RFC 104:** https://gdal.org/development/rfc/rfc104_gdal_cli.html
- **gdalraster Package:** https://usdaforestservice.github.io/gdalraster/
- **R6 Documentation:** https://r6.r-lib.org/
- **rlang Metaprogramming:** https://rlang.r-lib.org/

