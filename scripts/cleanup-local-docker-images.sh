#!/bin/bash

# cleanup-local-docker-images.sh
# Local Docker cleanup script for gdalcli Docker images
# Removes old local Docker images you've pulled, keeps the most recent base and runtime images
# Supports dry-run and force modes for safety

set -e

DRY_RUN=false
FORCE=false
REPO="ghcr.io/brownag/gdalcli"

usage() {
    echo "Usage: $0 [--dry-run] [--force] [--repo REPO]"
    echo "  --dry-run: Show what would be removed without actually removing"
    echo "  --force: Skip confirmation prompts"
    echo "  --repo REPO: Docker repository to clean (default: $REPO)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --repo)
            REPO="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Get all images for the repository
echo "Fetching Docker images for $REPO..."
images=$(docker images "$REPO" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || echo "")

if [ -z "$images" ]; then
    echo "No images found for $REPO"
    exit 0
fi

echo "Found images:"
echo "$images" | sort
echo

# Function to extract and find the maximum version for a given pattern
get_max_version() {
    local pattern="$1"
    local versions=()

    for img in $images; do
        tag="${img#*:}"
        if [[ $tag =~ $pattern ]]; then
            ver="${BASH_REMATCH[1]}"
            versions+=("$ver")
        fi
    done

    if [ ${#versions[@]} -eq 0 ]; then
        echo ""
        return
    fi

    # Sort versions numerically and get the latest
    printf '%s\n' "${versions[@]}" | sort -V | tail -1
}

# Patterns for different image types (matching your actual naming scheme)
deps_pattern='deps-gdal-(.+)-amd64'
runtime_pattern='gdal-(.+)-latest'

# Find the latest versions
deps_max=$(get_max_version "$deps_pattern")
runtime_max=$(get_max_version "$runtime_pattern")

echo "Latest versions found:"
[ -n "$deps_max" ] && echo "  Deps: $deps_max"
[ -n "$runtime_max" ] && echo "  Runtime: $runtime_max"
echo

# Build list of images to keep
keep_images=()
if [ -n "$deps_max" ]; then
    keep_images+=("$REPO:deps-gdal-${deps_max}-amd64")
fi
if [ -n "$runtime_max" ]; then
    keep_images+=("$REPO:gdal-${runtime_max}-latest")
fi

# Build list of images to remove (matching patterns but not in keep list)
remove_images=()
for img in $images; do
    tag="${img#*:}"
    if [[ $tag =~ $deps_pattern ]] || [[ $tag =~ $runtime_pattern ]]; then
        keep=false
        for keep_img in "${keep_images[@]}"; do
            if [ "$img" = "$keep_img" ]; then
                keep=true
                break
            fi
        done
        if [ "$keep" = false ]; then
            remove_images+=("$img")
        fi
    fi
done

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN MODE - No images will be removed"
    echo
    echo "Images to keep (${#keep_images[@]}):"
    for img in "${keep_images[@]}"; do
        echo "  [OK] $img"
    done
    echo
    echo "Images to remove (${#remove_images[@]}):"
    for img in "${remove_images[@]}"; do
        echo "  [FAIL] $img"
    done
    echo
    echo "Dry run complete."
    exit 0
fi

# Check if there are images to remove
if [ ${#remove_images[@]} -eq 0 ]; then
    echo "No old images to remove. All images are up to date."
    exit 0
fi

# Show what will be removed
echo "Images to keep (${#keep_images[@]}):"
for img in "${keep_images[@]}"; do
    echo "  [OK] $img"
done
echo
echo "Images to remove (${#remove_images[@]}):"
for img in "${remove_images[@]}"; do
    echo "  [FAIL] $img"
done
echo

# Safety check unless forced
if [ "$FORCE" = false ]; then
    read -p "Do you want to proceed with removing these images? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Remove images
echo "Removing images..."
removed_count=0
for img in "${remove_images[@]}"; do
    echo "Removing $img..."
    if docker rmi "$img" 2>/dev/null; then
        echo "  [OK] Successfully removed $img"
        ((removed_count++))
    else
        echo "  [FAIL] Failed to remove $img (may not exist or be in use)"
    fi
done

echo
echo "Cleanup complete. Successfully removed $removed_count out of ${#remove_images[@]} images."

# Optional: Run system prune to clean up any remaining artifacts
if [ "$FORCE" = true ] || [ "$DRY_RUN" = false ]; then
    echo "Running docker system prune to clean up remaining artifacts..."
    docker system prune -f >/dev/null 2>&1
    echo "System cleanup complete."
fi