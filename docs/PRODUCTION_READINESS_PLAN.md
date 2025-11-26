# Production Readiness Plan for gdalcli

## Overview

This plan addresses three major areas: (1) Documentation and exported functions, (2) gdalraster backend integration, and (3) CI/CD workflows. The goal is to make the package production-ready with comprehensive testing and reliable auto-generation.

---

## 1. Documentation & Exported Functions Streamlining

### Current State
- 82 auto-generated gdal_*.R function files
- 101 exported functions in NAMESPACE
- 154 .Rd documentation files (auto-generated via roxygen2)
- 1 vignette: vignettes/basic-functionality.Rmd
- README.md: Comprehensive (928 lines)
- docs/ folder: 4 files (VERSION_AWARE_GENERATION.md, VERSION_MATRIX.md, ADVANCED_FEATURES_GUIDE.md, release-branches.md)

### Issues Identified
1. **Documentation Coverage**: Roxygen2 auto-generates .Rd files from code comments, but examples vary in completeness
2. **Exported vs Internal**: 17 internal functions use @keywords internal, need audit of visibility
3. **Vignette Coverage**: Only 1 vignette exists; needs more practical examples
4. **README Size**: Extensive but may overwhelm users; needs better navigation
5. **Function Organization**: Auto-generated functions need consistent naming and documentation

### Actions Required

#### 1.1 Create Function Documentation Index
**Goal**: Make it easy for users to find functions by category and use case

Files to create:
- docs/FUNCTION_REFERENCE.md - Categorized function listing
  - Raster operations (gdal_raster_*)
  - Vector operations (gdal_vector_*)
  - Multidimensional operations (gdal_mdim_*)
  - VSI/Cloud operations (gdal_vsi_*)
  - Utility/discovery functions (gdal_list_commands, etc.)
  - Modifier functions (gdal_with_co, etc.)
- Each category includes: function name, brief description, link to help

Implementation:
- Auto-generate from NAMESPACE during build
- Build script: `build/generate_function_index.R`

#### 1.2 Enhance Vignette Coverage
**Goal**: Provide practical, real-world examples for common workflows

New vignettes to create:
- vignettes/raster-workflows.Rmd - Raster processing examples
- vignettes/vector-workflows.Rmd - Vector processing examples
- vignettes/pipeline-building.Rmd - Pipeline composition and GDALG persistence
- vignettes/cloud-storage.Rmd - S3, Azure, GCS examples with VSI handlers

Requirements:
- Each vignette: 500-1000 words
- Real data examples where possible (use system files or synthetic data)
- Show job building, rendering, and execution patterns
- Include error handling and best practices

#### 1.3 Create Getting Started Guide
**Goal**: New users should be productive in under 5 minutes

File to create:
- docs/GETTING_STARTED.md

Contents:
- Installation instructions (system deps, R package)
- Verify installation (check GDAL version, list commands)
- First job: Simple raster info example
- First pipeline: 2-step raster workflow
- Next steps: Pointers to detailed docs

#### 1.4 Audit and Document Exported Functions
**Goal**: Ensure all exported functions have clear documentation and serve a purpose

Actions:
- Review all 101 exported functions in NAMESPACE
- Update roxygen @export comments with:
  - Clear @title and @description
  - Meaningful @examples (where not auto-generated)
  - @seealso for related functions
  - @family tags for grouping
- Identify and consolidate overlapping functions
- Consider re-exporting helpers as internal (@keywords internal) if needed

Implementation:
- audit tool: Create docs/EXPORTS_AUDIT.md tracking this
- Manual review of core-*.R files
- Test that all exports are actually documented

#### 1.5 Streamline README
**Goal**: Make README more scannable and reference-friendly

Actions:
- Move detailed examples to vignettes/
- Keep README to ~300-400 lines
- Reorganize as:
  1. Quick intro (what, why, who)
  2. Installation
  3. Minimal example (5 lines)
  4. Key features (bulleted)
  5. Links to documentation
  6. System requirements
- Keep detailed examples in vignettes and FUNCTION_REFERENCE.md

---

## 2. gdalraster Backend Integration Enhancement

### Current State
- gdalraster in Suggests (optional dependency)
- Partial integration in:
  - core-explicit-args.R - Uses GDALAlg.getExplicitlySetArgs() for GDAL 3.12+
  - core-gdal-discovery.R - Uses gdal_commands from gdalraster
  - core-advanced-features.R - Advanced feature detection
  - core-vector-from-object.R - In-memory vector processing

### Features Not Yet Integrated
1. **GDALAlg class usage** - Only getExplicitlySetArgs() used, not full class API
2. **gdalraster version detection** - No automatic feature availability based on gdalraster version
3. **Rcpp bindings** - Advanced features (setVectorArgsFromObject, etc.) not implemented
4. **Performance paths** - No option to use gdalraster backend for faster execution when available
5. **Documentation** - Limited guidance on when/why to use gdalraster backend

### Actions Required

#### 2.1 Create Version Detection for gdalraster
**Goal**: Automatically detect gdalraster capabilities and enable features

File to create/update:
- R/core-gdalraster-detection.R (new)

Contents:
- Function: `.check_gdalraster_version(min_version = "2.2.0")`
  - Check if gdalraster is installed
  - Parse version from packageVersion()
  - Compare against minimum required
  - Return boolean or throw informative error

- Function: `.get_gdalraster_features()`
  - Return list of available features by gdalraster version
  - gdalraster 2.2.0+: getExplicitlySetArgs, gdal_commands
  - gdalraster 2.3.0+: setVectorArgsFromObject, advanced features
  - Enables version-conditional code paths

#### 2.2 Implement setVectorArgsFromObject Integration
**Goal**: Use gdalraster's in-memory vector processing when available

File to update:
- R/core-vector-from-object.R (enhance existing)

Actions:
- Detect if gdalraster 2.3.0+ available
- When user passes R data.frame/sf object to vector function:
  - Try to use gdalraster::setVectorArgsFromObject() first
  - Fall back to temp file approach if not available
- Document this feature with examples

Implementation:
- Add helper: `.vector_from_object_with_gdalraster()`
- Update gdal_job_run() dispatch for vector jobs with R objects
- Add examples to core-vector-from-object.R

#### 2.3 Enhance gdalraster Backend for Job Execution
**Goal**: Make gdalraster backend a first-class execution option

Files to update:
- R/core-gdal_run.R

Actions:
- Add `.run_with_gdalraster()` function for job execution
- Implement gdalraster algorithm execution path:
  - Map gdal_job to gdalraster algorithm
  - Execute via gdalraster Rcpp bindings
  - Return result in same format as processx backend
- Add parameter to gdal_job_run(): `backend = c("processx", "gdalraster", "reticulate")`
- Auto-select gdalraster if available for non-CLI operations

Benefits:
- Faster execution for pure algorithmic operations
- No subprocess overhead
- Better integration with R data structures

#### 2.4 Add gdalraster Backend Documentation
**Goal**: Help users understand when and how to use gdalraster backend

Files to create/update:
- docs/GDALRASTER_INTEGRATION.md (new)

Contents:
- What is gdalraster backend
- Version requirements and features by version
- Installation instructions
- Performance comparison with processx backend
- Use cases where gdalraster is preferred
- Examples of explicit backend selection

#### 2.5 Update ADVANCED_FEATURES_GUIDE.md
**Goal**: Document all gdalraster-enabled features

Updates needed:
- Add section on gdalraster version detection
- Document getExplicitlySetArgs() with examples
- Document setVectorArgsFromObject() workflow
- Add performance tuning section
- Note version requirements clearly

---

## 3. CI/CD Workflow Modernization

### Current State
- Single workflow: .github/workflows/build-gdal-dynamic.yml
- Purpose: Build Docker images for specific GDAL versions
- Triggered: Manual (workflow_dispatch)
- Functions: Version parsing, Docker build, release creation

### Gaps Identified
1. **No package checking** - No `R CMD check` in any workflow
2. **No testing** - No testthat or unit tests run
3. **No auto-generation in CI** - API generation not tested/validated in CI
4. **No matrix testing** - Only builds single GDAL version at a time
5. **No documentation build** - README, vignettes, man pages not generated in CI
6. **No cross-version validation** - No tests across GDAL 3.11, 3.12, etc.

### Actions Required

#### 3.1 Create Standard Package Check Workflow
**Goal**: Validate package integrity on every push

File to create:
- .github/workflows/check.yml

Contents:
```yaml
name: Package Check

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  check:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        r-version: ['4.1', '4.2', '4.3', '4.4']

    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.r-version }}
      - name: Install system dependencies
        run: |
          # GDAL setup (use existing package system)
      - uses: r-lib/actions/setup-renv@v2
      - name: Run R CMD check
        uses: r-lib/actions/check-r-package@v2
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: check-results-${{ matrix.os }}-r${{ matrix.r-version }}
          path: |
            ${{ github.workspace }}/check/
            ${{ github.workspace }}/tests/
```

#### 3.2 Create API Generation Validation Workflow
**Goal**: Test auto-generation with multiple GDAL versions

File to create:
- .github/workflows/generate-api.yml

Contents:
```yaml
name: API Generation & Validation

on:
  push:
    branches: [main]
    paths:
      - 'build/generate_gdal_api.R'
      - 'build/validate_generated_api.R'
  workflow_dispatch:
    inputs:
      gdal_version:
        description: 'GDAL version to test'
        default: '3.11.4'

jobs:
  test-generation:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        gdal-version: ['3.11.4', '3.12.0']

    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
      - name: Install GDAL ${{ matrix.gdal-version }}
        run: |
          # Install specific GDAL version
      - name: Run API generation
        run: Rscript build/generate_gdal_api.R
      - name: Validate generated API
        run: Rscript build/validate_generated_api.R
      - name: Check for regressions
        run: |
          # Compare generated files against baseline
          # Ensure all functions regenerated, examples present, etc.
      - name: Upload validation report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: api-validation-gdal${{ matrix.gdal-version }}
          path: validation-report.txt
```

#### 3.3 Create Documentation Build Workflow
**Goal**: Build and validate all documentation

File to create:
- .github/workflows/docs.yml

Contents:
```yaml
name: Documentation Build

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - 'vignettes/**'
      - 'README.Rmd'
  pull_request:
    branches: [main]
    paths:
      - 'docs/**'
      - 'vignettes/**'
      - 'README.Rmd'

jobs:
  build-docs:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
      - name: Install R packages
        run: |
          install.packages(c('knitr', 'rmarkdown', 'devtools'))
      - name: Render vignettes
        run: |
          devtools::build_vignettes()
      - name: Render README
        run: |
          rmarkdown::render('README.Rmd')
      - name: Check links in docs
        run: |
          # Use markdown-link-check or similar
      - name: Upload built docs
        uses: actions/upload-artifact@v3
        with:
          name: documentation
          path: |
            vignettes/
            README.html
            docs/
```

#### 3.4 Create Cross-Version Testing Workflow
**Goal**: Test package with multiple GDAL and R versions

File to create:
- .github/workflows/test-matrix.yml

Contents:
```yaml
name: Cross-Version Testing

on:
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 1 * *'  # Monthly

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        gdal-version: ['3.11.3', '3.11.4', '3.12.0']
        r-version: ['4.1', '4.2', '4.3', '4.4']
        exclude:
          # Skip unlikely combinations
          - gdal-version: '3.12.0'
            r-version: '4.1'

    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.r-version }}
      - name: Install GDAL ${{ matrix.gdal-version }}
        run: |
          # Docker or apt approach
      - name: Install R dependencies
        run: |
          devtools::install_deps(dependencies = TRUE)
      - name: Run tests
        run: |
          devtools::test()
      - name: Run examples
        run: |
          # Run all @examples sections from .Rd files
```

#### 3.5 Update build-gdal-dynamic.yml
**Goal**: Keep existing workflow but add validation steps

Actions:
- Add API generation step after Docker build
- Run validate_generated_api.R
- Report validation results
- Only create release if validation passes
- Upload validation artifacts

#### 3.6 Create Workflow Coordination File
**Goal**: Document which workflows run when and why

File to create:
- docs/CI_CD_WORKFLOWS.md

Contents:
- check.yml: Runs on every push/PR, validates package integrity
- generate-api.yml: Runs when build scripts change, tests auto-generation
- docs.yml: Runs when docs/vignettes change, builds and validates docs
- test-matrix.yml: Monthly schedule, cross-version testing
- build-gdal-dynamic.yml: Manual dispatch, creates release builds
- Workflow dependencies and coordination

---

## 4. Implementation Timeline

### Phase 1: Documentation (Week 1-2)
- Create FUNCTION_REFERENCE.md (auto-generated)
- Create GETTING_STARTED.md
- Create gdalraster integration docs
- Streamline README

**Deliverables:**
- docs/FUNCTION_REFERENCE.md
- docs/GETTING_STARTED.md
- docs/GDALRASTER_INTEGRATION.md
- Updated README.md
- Updated ADVANCED_FEATURES_GUIDE.md

### Phase 2: gdalraster Integration (Week 2-3)
- Implement version detection
- Enhance vector-from-object support
- Add gdalraster backend execution path
- Update existing core files

**Deliverables:**
- R/core-gdalraster-detection.R (new)
- Updated R/core-vector-from-object.R
- Updated R/core-gdal_run.R
- Tests for new features

### Phase 3: CI/CD Workflows (Week 3-4)
- Create all new workflow files
- Update existing build-gdal-dynamic.yml
- Document in CI_CD_WORKFLOWS.md
- Test workflows with dummy runs

**Deliverables:**
- .github/workflows/check.yml
- .github/workflows/generate-api.yml
- .github/workflows/docs.yml
- .github/workflows/test-matrix.yml
- Updated build-gdal-dynamic.yml
- docs/CI_CD_WORKFLOWS.md

### Phase 4: Vignettes & Polish (Week 4-5)
- Create additional vignettes
- Run through all documentation
- Test examples end-to-end
- Create FUNCTION_REFERENCE.md if not auto-generated

**Deliverables:**
- vignettes/raster-workflows.Rmd
- vignettes/vector-workflows.Rmd
- vignettes/pipeline-building.Rmd
- vignettes/cloud-storage.Rmd
- All examples tested and working

---

## 5. Success Criteria

### Documentation & Functions
- [ ] All 101 exported functions documented with roxygen2
- [ ] FUNCTION_REFERENCE.md auto-generated and complete
- [ ] GETTING_STARTED.md covers 80% of user first steps
- [ ] 4-5 comprehensive vignettes with working examples
- [ ] README < 400 lines with clear structure
- [ ] No broken links in documentation

### gdalraster Integration
- [ ] Version detection works for all supported versions
- [ ] setVectorArgsFromObject fallback path implemented
- [ ] gdalraster backend option available in gdal_job_run()
- [ ] Performance comparison documented
- [ ] Tests pass for gdalraster backend
- [ ] Clear version requirement notes in docs

### CI/CD
- [ ] Package check passes on all platforms/R versions
- [ ] API generation tested with GDAL 3.11.x and 3.12.x
- [ ] Validation report generated and reviewed
- [ ] All new vignettes build without errors
- [ ] Documentation links verified
- [ ] Cross-version tests pass monthly
- [ ] Workflows execute without warnings

---

## 6. Maintenance & Monitoring

### Regular Tasks
- **Monthly**: Run cross-version test matrix, review failure patterns
- **Per GDAL release**: Test API generation with new GDAL version
- **Per PR**: Package check workflow validates changes
- **Quarterly**: Review documentation for gaps or outdated content

### Monitoring Metrics
- Package check pass rate: Target 100%
- API generation time: Baseline GDAL 3.11.4 time
- Documentation coverage: All exported functions in FUNCTION_REFERENCE.md
- Example consistency: All vignette examples runnable
- gdalraster adoption: Track feature usage via version checks

---

## Notes

- This plan assumes continued maintenance of the single-repository approach
- Docker containers in build-gdal-dynamic.yml provide isolated GDAL environments
- R-Universe integration enables easy installation of dynamic builds
- Focus on production readiness: clear documentation, reliable CI/CD, robust backends
