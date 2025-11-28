#!/bin/bash
# Quick reference: Using the new dynamic GDAL build system
# 
# This script shows common workflows for building gdalcli with different GDAL versions

set -e

REPO_OWNER="${REPO_OWNER:-brownag}"
REPO_NAME="${REPO_NAME:-gdalcli}"
WORKFLOW_FILE="build-releases.yml"

# ============================================================================
# Common Build Scenarios
# ============================================================================

echo "=== gdalcli Dynamic GDAL Build System ==="
echo ""
echo "This system allows you to build gdalcli with ANY GDAL version"
echo ""

# Scenario 1: Build a stable GDAL release
build_stable_version() {
    local version=$1
    echo "Building stable GDAL $version from GitHub releases..."
    gh workflow run $WORKFLOW_FILE \
        -f gdal_version="$version" \
        -f gdal_release_type="tagged" \
        -f create_release="true" \
        -R "$REPO_OWNER/$REPO_NAME"
    echo "✓ Workflow triggered for GDAL $version"
}

# Scenario 2: Build latest development version
build_dev_version() {
    echo "Building latest GDAL from main branch..."
    gh workflow run $WORKFLOW_FILE \
        -f gdal_version="latest" \
        -f gdal_release_type="dev" \
        -f create_release="true" \
        -R "$REPO_OWNER/$REPO_NAME"
    echo "✓ Workflow triggered for GDAL development version"
}

# Scenario 3: Build multiple versions
build_multiple_versions() {
    local versions=("$@")
    echo "Building multiple GDAL versions..."
    for version in "${versions[@]}"; do
        echo "Triggering build for GDAL $version..."
        gh workflow run $WORKFLOW_FILE \
            -f gdal_version="$version" \
            -f gdal_release_type="tagged" \
            -f create_release="true" \
            -R "$REPO_OWNER/$REPO_NAME"
        sleep 2  # Small delay to avoid rate limiting
    done
    echo "✓ All builds triggered"
}

# Scenario 4: Build locally with Docker (without workflow)
build_local_docker() {
    local gdal_version=${1:-3.11.1}
    local release_type=${2:-tagged}
    
    echo "Building locally: GDAL $gdal_version ($release_type)"
    docker build \
        --build-arg GDAL_VERSION="$gdal_version" \
        --build-arg GDAL_RELEASE_TYPE="$release_type" \
        --target runtime \
        -f .github/dockerfiles/Dockerfile.template \
        -t "gdalcli:${gdal_version}-prod" \
        .
    echo "✓ Docker image built: gdalcli:${gdal_version}-prod"
}

# Scenario 5: Test API generation locally
test_api_generation() {
    local gdal_version=${1:-3.11.1}
    
    echo "Testing API generation for GDAL $gdal_version..."
    docker run --rm \
        --build-arg GDAL_VERSION="$gdal_version" \
        --build-arg GDAL_RELEASE_TYPE="tagged" \
        --target base \
        -f .github/dockerfiles/Dockerfile.template \
        gdalcli:${gdal_version}-test \
        bash -c "Rscript build/generate_gdal_api.R && echo '✓ API generated successfully'"
}

# ============================================================================
# Main Menu
# ============================================================================

show_menu() {
    cat << 'EOF'

Choose an action:

1. Build stable GDAL version (e.g., 3.11.1)
2. Build latest GDAL development version
3. Build multiple GDAL versions
4. Build locally with Docker
5. Check workflow status
6. View release branch status
7. List available GDAL releases on GitHub

EOF
}

show_supported_versions() {
    echo ""
    echo "Commonly available GDAL versions:"
    echo "  - 3.11.1 (stable)"
    echo "  - 3.12.0 (newer)"
    echo "  - 3.10.3 (LTS)"
    echo "  - 3.9.5 (older)"
    echo "  - latest (development from main branch)"
    echo ""
    echo "For a full list of releases, visit:"
    echo "  https://github.com/OSGeo/gdal/releases"
}

check_workflow_status() {
    echo "Recent workflow runs:"
    gh run list \
        -w $WORKFLOW_FILE \
        --limit 10 \
        -R "$REPO_OWNER/$REPO_NAME" \
        --json status,conclusion,createdAt,displayTitle
}

check_release_branches() {
    echo "Release branches:"
    gh api repos/"$REPO_OWNER"/"$REPO_NAME"/branches \
        --jq '.[] | select(.name | startswith("release/gdal")) | {name, protected: .protected}'
}

list_gdal_releases() {
    echo "Recent GDAL releases from GitHub:"
    curl -s https://api.github.com/repos/OSGeo/gdal/releases?per_page=20 \
        | jq -r '.[] | "\(.tag_name): \(.name)"' | head -15
}

# ============================================================================
# Main execution
# ============================================================================

if [[ $# -eq 0 ]]; then
    show_menu
    read -p "Enter choice (1-7): " choice
else
    choice=$1
fi

case $choice in
    1)
        show_supported_versions
        read -p "Enter GDAL version to build (e.g., 3.11.1): " version
        build_stable_version "$version"
        ;;
    2)
        build_dev_version
        ;;
    3)
        read -p "Enter GDAL versions (space-separated, e.g., '3.11.1 3.12.0'): " versions
        build_multiple_versions $versions
        ;;
    4)
        read -p "Enter GDAL version (default: 3.11.1): " version
        version=${version:-3.11.1}
        read -p "Enter release type - tagged|latest|dev (default: tagged): " release_type
        release_type=${release_type:-tagged}
        build_local_docker "$version" "$release_type"
        ;;
    5)
        check_workflow_status
        ;;
    6)
        check_release_branches
        ;;
    7)
        list_gdal_releases
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "Done!"
