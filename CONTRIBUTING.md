# Contributing to gdalcli

Contributions are welcome! Whether you're fixing a bug, adding a feature, or improving documentation, your help is appreciated.

## Before You Start

**Please raise an issue or discussion first** before submitting a pull request. This helps us:

- Avoid duplicate work
- Discuss the best approach for your contribution
- Ensure the change aligns with the project's goals
- Provide early feedback on your ideas

## Pull Request Process

1. Fork the repository
2. Create a feature branch from `main` (e.g., `git checkout -b feature/my-feature`)
3. Make your changes and commit with clear messages
4. Push to your fork and open a Pull Request
5. Reference the related issue in your PR description

## Guidelines

- Follow existing code style and patterns in the repository
- Add tests for new functionality
- Update documentation as needed
- Keep commits focused and atomic
- Write descriptive commit messages

## CI/CD Workflows

The project uses automated testing and building via GitHub Actions. As a contributor, you should be aware of:

### Automatic Testing on Pull Requests

When you create a pull request, the following workflows automatically trigger:

- **R-CMD-check-ubuntu.yml**: Comprehensive R CMD check on native Ubuntu/GitHub runners with GDAL 3.11+ from ubuntugis PPA
- **R-CMD-check-docker.yml**: R CMD check in isolated Docker containers with controlled GDAL versions

**All tests must pass** before your PR can be merged.

#### R-CMD-check-ubuntu.yml

- **Environment**: Ubuntu 24.04 with GDAL 3.11+ from ubuntugis PPA
- **Coverage**: Full R CMD check including vignettes, tests, and gdalraster compatibility
- **When to use for debugging**: Standard CI issues, dependency problems on Ubuntu

#### R-CMD-check-docker.yml

- **Environment**: Custom Docker images with controlled GDAL versions
- **Coverage**: Full R CMD check with pre-installed dependencies
- **When to use for debugging**: Environment-specific issues, GDAL version compatibility, Docker-related problems

### Common CI Failures and Debugging

If tests fail:

1. **Check the GitHub Actions tab** for detailed error logs
2. **Read the error message carefully** - is it Ubuntu-specific or Docker-specific?
3. **Common issues**:
   - GDAL version compatibility - check if the issue appears in both workflows
   - Missing dependencies - verify all imports are declared
   - Vignette build failures - check for GDAL-dependent examples
   - Code style issues - ensure roxygen2 documentation is up to date

4. **For Docker-specific issues**:
   - Examine the R-CMD-check-docker workflow logs for container-specific errors
   - Docker issues often relate to GDAL compilation, system dependencies, or environment setup

### Build Workflows (Manual Trigger)

These workflows are triggered manually via GitHub Actions when infrastructure updates are needed:

#### build-docker-images.yml

- **Purpose**: Build GDAL base images and gdalcli runtime images (consolidated workflow)
- **Base Image Output**: `ghcr.io/brownag/gdalcli:deps-gdal-X.Y.Z-amd64`
- **Runtime Image Output**: `ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`
- **Manual parameters**: `gdal_version`, `image_stage` (both/deps/full), `push_images`
- **Trigger**: Weekly schedule (Saturdays), main branch pushes, or manual dispatch
- **When to use**: Automated weekly builds or when GDAL dependencies need updates

#### build-releases.yml

- **Purpose**: Dynamic package builds and GitHub releases
- **Manual parameters**: `gdal_version`, `package_version`, `create_release`, etc.
- **Output**: Release branches, GitHub releases, package binaries
- **When to use**: Creating new package releases for specific GDAL versions

### Docker Image Architecture

The project uses a two-layer Docker architecture for consistent GDAL environments:

**Base Images** (`ghcr.io/brownag/gdalcli:deps-gdal-X.Y.Z-amd64`)

- Contains: GDAL X.Y.Z, R, and all package dependencies (no gdalcli package)
- Purpose: Reusable foundation for CI and development
- Usage in CI: R-CMD-check-docker workflow tests against these images
- When updated: When GDAL versions change or dependencies update

**Runtime Images** (`ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`)

- Contains: Complete gdalcli package installed and tested
- Purpose: Production-ready images for users and deployment
- When updated: Weekly or when package changes significantly

**Relationship:**

- Base images provide the GDAL + R foundation
- Runtime images extend base images with the compiled gdalcli package
- CI workflows use base images for testing (faster, no package pre-install needed)
- Users can pull runtime images for ready-to-use gdalcli environments

### Workflow Selection Guide

| Scenario | Recommended Workflow | Notes |
|----------|---------------------|-------|
| Code changes | R-CMD-check-ubuntu + R-CMD-check-docker | Both run automatically on PRs |
| GDAL version updates | build-docker-images | Builds both base and runtime images |
| Package releases | build-releases | Manual workflow with version parameters |
| Docker issues | R-CMD-check-docker | Isolated testing environment |
| Performance testing | R-CMD-check-docker | Consistent environment |

### Docker Image Maintenance

The project maintains Docker images for CI/CD and user deployment. To prevent accumulation of old images, automated cleanup is available:

#### Local Docker Cleanup

Use this script to remove old local Docker images you've pulled locally:

```bash
# Dry run (recommended first)
./scripts/cleanup-local-docker-images.sh --dry-run

# Remove old images (keeps latest base and runtime images)
./scripts/cleanup-local-docker-images.sh --force
```

**Options:**

- `--dry-run`: Show what would be removed without actually removing
- `--force`: Skip confirmation prompts
- `--repo REPO`: Specify different repository (default: `ghcr.io/brownag/gdalcli`)

#### Remote GHCR Cleanup

Use the GitHub CLI script to clean up old images from GitHub Container Registry remotely:

```bash
# Dry run (recommended first)
./scripts/cleanup-ghcr-images.sh --dry-run

# Remove old GDAL versions (keeps 3 most recent)
./scripts/cleanup-ghcr-images.sh --force
```

Alternatively, the `cleanup-ghcr.yml` GitHub Actions workflow can run the cleanup manually:

- **Manual Trigger**: Actions → "Cleanup GHCR Images" → Run workflow
- **Retention**: Keeps the 3 most recent GDAL versions (all images per version are preserved)
- **Safety**: Supports dry-run mode for testing (enabled by default)

**Manual workflow options:**

- `dry_run`: `true` (default) or `false`
- `keep_versions`: Number of recent GDAL versions to keep (default: 3)
- `force`: Skip confirmation prompts (default: false)

#### Image Types

- **Base Images**: `ghcr.io/brownag/gdalcli:deps-gdal-X.Y.Z-amd64`
  - Used for CI testing and as foundation for runtime images
  - Cleanup keeps all images for the most recent GDAL versions

- **Runtime Images**: `ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`
  - Complete images with gdalcli package installed
  - Cleanup keeps all images for the most recent GDAL versions

## Questions?

If you have questions about contributing, open a discussion in the repository or file an issue.

Thank you for your interest in gdalcli!
