#!/bin/bash
# Test Docker builds locally before pushing to CI
# This script builds and tests all stages of the Docker image

set -e

GDAL_VERSION="${GDAL_VERSION:-3.11.4}"
REPO_NAME="gdalcli-local"

echo "=========================================="
echo "Testing Docker builds for GDAL ${GDAL_VERSION}"
echo "=========================================="

# Build arguments
BUILD_ARGS="--build-arg GDAL_VERSION=${GDAL_VERSION} \
  --build-arg GDAL_BUILD_MODE=osgeo \
  --build-arg GDAL_RELEASE_TYPE=tagged \
  --build-arg GDAL_IMAGE_TAG=ubuntu-small-${GDAL_VERSION} \
  --build-arg R_VERSION=latest \
  --build-arg PACKAGE_VERSION=0.2.0"

# ============================================================================
# Test 1: Build deps image (r-packages stage)
# ============================================================================
echo ""
echo "=== Building deps image (r-packages stage) ==="
docker build \
  -f .github/dockerfiles/Dockerfile.template \
  --target r-packages \
  ${BUILD_ARGS} \
  -t ${REPO_NAME}:deps-gdal-${GDAL_VERSION}-amd64 \
  .

echo ""
echo "=== Testing deps image ==="
docker run --rm ${REPO_NAME}:deps-gdal-${GDAL_VERSION}-amd64 bash -c '
  set -e
  echo "--- GDAL version ---"
  gdal --version
  gdal --help-general
  echo "--- R version ---"
  R --version | head -3
  echo "--- R packages ---"
  Rscript -e "library(processx); library(yyjsonr); library(gdalraster); library(devtools); cat(\"All deps present\\n\")"
  echo "✓ Deps image tests passed"
'

# ============================================================================
# Test 2: Build full runtime image (gdalcli-runtime stage)
# ============================================================================
echo ""
echo "=== Building full runtime image (gdalcli-runtime stage) ==="
docker build \
  -f .github/dockerfiles/Dockerfile.template \
  --target gdalcli-runtime \
  ${BUILD_ARGS} \
  -t ${REPO_NAME}:gdal-${GDAL_VERSION}-latest \
  .

echo ""
echo "=== Testing full runtime image ==="
docker run --rm ${REPO_NAME}:gdal-${GDAL_VERSION}-latest bash -c '
  set -e
  echo "--- GDAL version ---"
  gdal --version
  echo "--- gdalcli capabilities ---"
  Rscript -e "library(gdalcli); print(gdal_capabilities()); cat(\"gdalcli loaded successfully\n\")"
  echo "--- Basic pipeline test ---"
  Rscript -e "
    library(gdalcli)
    job <- gdal_raster_info(input = \"/vsimem/test.tif\")
    cat(\"Pipeline created successfully\n\")
  "
  echo "✓ Full runtime image tests passed"
'

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=========================================="
echo "✓ All Docker builds and tests passed!"
echo "=========================================="
echo ""
echo "Built images:"
echo "  - ${REPO_NAME}:deps-gdal-${GDAL_VERSION}-amd64"
echo "  - ${REPO_NAME}:gdal-${GDAL_VERSION}-latest"
echo ""
echo "To test interactively:"
echo "  docker run -it --rm ${REPO_NAME}:deps-gdal-${GDAL_VERSION}-amd64 bash"
echo "  docker run -it --rm ${REPO_NAME}:gdal-${GDAL_VERSION}-latest R"
echo ""
echo "To clean up:"
echo "  docker rmi ${REPO_NAME}:deps-gdal-${GDAL_VERSION}-amd64"
echo "  docker rmi ${REPO_NAME}:gdal-${GDAL_VERSION}-latest"
echo ""
