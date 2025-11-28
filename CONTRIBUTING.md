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

### Automatic Testing

**Pull requests automatically trigger:**

- **R-CMD-check-ubuntu.yml**: Tests on Ubuntu runners with GDAL from ubuntugis PPA
- **R-CMD-check-docker.yml**: Tests in Docker containers with controlled environments

**All tests must pass** before your PR can be merged. If tests fail:

1. Check the GitHub Actions tab for detailed error logs
2. Common issues: GDAL compatibility, missing dependencies, vignette build failures
3. For Docker-specific issues, examine the R-CMD-check-docker workflow logs

### When Workflows Run

| Event | Workflows Triggered | Purpose |
|-------|-------------------|---------|
| Push to main | R-CMD-check-ubuntu, R-CMD-check-docker, build-runtime-images | Full CI + weekly image builds |
| Pull Request | R-CMD-check-ubuntu, R-CMD-check-docker | PR validation |
| Manual trigger | build-base-images, build-releases | Infrastructure/package releases |

### Release Process

Package releases are handled through the **build-releases.yml** workflow:

1. Manual trigger with GDAL version and package version parameters
2. Builds package in Docker container with specified GDAL version
3. Creates release branch and GitHub release
4. Contributors don't need to worry about releases unless specifically requested

### Docker Images

The project maintains Docker images for consistent testing:

- **Base images** (`ghcr.io/brownag/gdalcli:base-gdal-X.Y.Z-amd64`): Built via build-base-images.yml
- **Runtime images** (`ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`): Built via build-runtime-images.yml

These provide controlled GDAL environments for testing. If you encounter GDAL-related issues, check if the Docker workflow reveals different behavior than the Ubuntu workflow.

## Questions?

If you have questions about contributing, open a discussion in the repository or file an issue.

Thank you for your interest in gdalcli!
