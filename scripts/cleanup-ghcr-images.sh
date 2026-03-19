#!/bin/bash

# cleanup-ghcr-images.sh
# GitHub CLI script to cleanup old Docker images from GHCR
# Removes images for GDAL versions not in .github/versions.json
# Run this locally to clean up old images from GitHub Container Registry

set -e

# Configuration
REPO_OWNER="brownag"
REPO_NAME="gdalcli"
VERSIONS_FILE=".github/versions.json"
MODE="unsupported"  # "unsupported" to remove versions not in versions.json, or "keep-n" to keep N most recent
KEEP_VERSIONS=3
DRY_RUN=false
FORCE=false

usage() {
    echo "Usage: $0 [--dry-run] [--force] [--mode MODE] [--keep VERSIONS] [--owner OWNER] [--repo REPO]"
    echo "  --dry-run: Show what would be removed without actually removing"
    echo "  --force: Skip confirmation prompts"
    echo "  --mode MODE: Cleanup strategy (default: $MODE)"
    echo "    unsupported: Remove images for GDAL versions not in .github/versions.json"
    echo "    keep-n: Keep only the N most recent GDAL versions (all images preserved per version)"
    echo "  --keep VERSIONS: When using keep-n mode, number of recent versions to keep (default: $KEEP_VERSIONS)"
    echo "                   All images for each kept GDAL version will be preserved"
    echo "  --owner OWNER: Repository owner (default: $REPO_OWNER)"
    echo "  --repo REPO: Repository name (default: $REPO_NAME)"
    echo
    echo "Requires GitHub CLI (gh) to be authenticated:"
    echo "  gh auth login"
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
        --mode)
            MODE="$2"
            shift 2
            ;;
        --keep)
            KEEP_VERSIONS="$2"
            shift 2
            ;;
        --owner)
            REPO_OWNER="$2"
            shift 2
            ;;
        --repo)
            REPO_NAME="$2"
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

# Check if gh CLI is available and authenticated
if ! command -v gh &> /dev/null; then
    echo "[ERROR] GitHub CLI (gh) is not installed. Please install it first:"
    echo "   https://cli.github.com/"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "[ERROR] GitHub CLI is not authenticated. Please run:"
    echo "   gh auth login"
    exit 1
fi

# Check if token has packages scope
if ! gh auth token | gh api /user/packages?package_type=container &>/dev/null; then
    echo "[ERROR] Your GitHub token doesn't have packages permissions."
    echo "   Required scopes: read:packages (and write:packages for deletion)"
    echo
    echo "   Please re-authenticate with packages permissions:"
    echo "   gh auth login --scopes read:packages,write:packages,repo"
    echo
    echo "   Or add scopes to existing authentication:"
    echo "   gh auth refresh --scopes read:packages,write:packages"
    exit 1
fi

# Load supported versions from versions.json if using unsupported mode
declare -A supported_versions
if [ "$MODE" = "unsupported" ]; then
    if [ ! -f "$VERSIONS_FILE" ]; then
        echo "[ERROR] Mode is 'unsupported' but $VERSIONS_FILE not found"
        echo "Please ensure .github/versions.json exists or use --mode keep-n"
        exit 1
    fi
    
    echo "[CONFIG] Reading supported versions from $VERSIONS_FILE..."
    # Parse supported versions using jq
    supported_list=$(jq -r '.supported[]' "$VERSIONS_FILE" 2>/dev/null)
    
    if [ -z "$supported_list" ]; then
        echo "[ERROR] Could not parse supported versions from $VERSIONS_FILE"
        exit 1
    fi
    
    while IFS= read -r version; do
        supported_versions["$version"]=1
    done <<< "$supported_list"
    
    echo "[CONFIG] Supported GDAL versions from $VERSIONS_FILE:"
    for ver in "${!supported_versions[@]}"; do
        echo "  [OK] GDAL $ver"
    done
fi

echo "[ACTION] GHCR Cleanup Script"
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Mode: $MODE"
if [ "$MODE" = "unsupported" ]; then
    echo "Action: Remove images for unsupported GDAL versions"
else
    echo "Keep most recent GDAL versions: $KEEP_VERSIONS (all images per version)"
fi
if [ "$DRY_RUN" = true ]; then
    echo "Mode: DRY RUN (no changes will be made)"
else
    echo "Mode: LIVE RUN (images will be deleted)"
fi
echo

# Get all container packages for this repository
echo "[PKG] Fetching container packages..."
echo "   Using user packages endpoint..."

# Use user packages endpoint (packages are owned by the user, not org)
packages=$(gh api "/user/packages?package_type=container" \
    --jq ".[] | select(.repository.name == \"$REPO_NAME\") | .name" 2>&1)

api_exit_code=$?
if [ $api_exit_code -ne 0 ]; then
    echo "   User packages endpoint failed (exit code: $api_exit_code): $packages"
fi

# Check if we got a valid response
if [[ "$packages" == *"Not Found"* ]] || [[ "$packages" == *"403"* ]] || [[ "$packages" == *"404"* ]]; then
    echo "[ERROR] API call failed: $packages"
    echo "This might mean you don't have permission to access packages."
    exit 1
fi

if [ -z "$packages" ] || [[ "$packages" == *"[]"* ]]; then
    echo "No container packages found for $REPO_OWNER/$REPO_NAME"
    echo "This might mean:"
    echo "  - No Docker images have been built and pushed to GHCR yet"
    echo "  - The images exist but you don't have permission to list them"
    echo "  - The repository has no container packages"
    echo
    echo "To check if images exist, you can try:"
    echo "  docker pull ghcr.io/$REPO_OWNER/$REPO_NAME:deps-gdal-3.11.4-amd64"
    echo "  docker pull ghcr.io/$REPO_OWNER/$REPO_NAME:gdal-3.11.4-latest"
    echo
    echo "If images exist but this script can't find them, the issue might be with API permissions."
    exit 0
fi

echo "Found packages:"
echo "$packages" | sed 's/^/  - /'
echo

total_removed=0

# Process each package
while IFS= read -r package; do
    if [ -z "$package" ]; then continue; fi

    echo "[FIND] Processing package: $package"

    # Get all versions for this package with their tags
    echo "  Fetching version details..."
    all_versions=$(gh api "/user/packages/container/$package/versions" \
        --jq '.[] | {id: .id, created_at: .created_at, tags: (.metadata.container.tags // [])}')

    # Parse versions and group by GDAL version
    declare -A gdal_versions
    declare -A version_details

    while IFS= read -r version_json; do
        if [ -z "$version_json" ]; then continue; fi

        version_id=$(echo "$version_json" | jq -r '.id')
        created_at=$(echo "$version_json" | jq -r '.created_at')
        tags=$(echo "$version_json" | jq -r '.tags[]')

        # Extract GDAL version from tags (full version X.Y.Z)
        gdal_ver=""
        for tag in $tags; do
            if [[ $tag =~ gdal-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
                gdal_ver="${BASH_REMATCH[1]}"
                break
            elif [[ $tag =~ deps-gdal-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
                gdal_ver="${BASH_REMATCH[1]}"
                break
            fi
        done

        # If no GDAL version found in tags, use "unknown"
        if [ -z "$gdal_ver" ]; then
            gdal_ver="unknown"
        fi

        # Store version details
        version_details["$version_id"]="$created_at|$tags|$gdal_ver"

        # Track latest creation time for each GDAL version
        if [ -z "${gdal_versions[$gdal_ver]}" ] || [ "$created_at" \> "${gdal_versions[$gdal_ver]}" ]; then
            gdal_versions[$gdal_ver]="$created_at"
        fi
    done <<< "$(echo "$all_versions" | jq -c '.')"

    # Determine which GDAL versions to keep based on mode
    declare -a keep_gdal_vers
    
    if [ "$MODE" = "unsupported" ]; then
        # Keep only supported versions from versions.json
        for gdal_ver in "${!gdal_versions[@]}"; do
            if [[ -v supported_versions[$gdal_ver] ]]; then
                keep_gdal_vers+=("$gdal_ver")
            fi
        done
    else
        # keep-n mode: Sort GDAL versions by creation time (newest first) and keep top N
        keep_gdal_vers=($(for ver in "${!gdal_versions[@]}"; do
            echo "${gdal_versions[$ver]}|$ver"
        done | sort -r | head -n "$KEEP_VERSIONS" | cut -d'|' -f2))
    fi

    # Build lists of versions to keep and remove
    keep_versions=()
    remove_versions=()

    for version_id in "${!version_details[@]}"; do
        details="${version_details[$version_id]}"
        created_at=$(echo "$details" | cut -d'|' -f1)
        tags=$(echo "$details" | cut -d'|' -f2-)
        gdal_ver=$(echo "$details" | cut -d'|' -f3)

        # Check if this GDAL version should be kept
        should_keep=false
        for keep_gdal_ver in "${keep_gdal_vers[@]}"; do
            if [ "$gdal_ver" = "$keep_gdal_ver" ]; then
                should_keep=true
                break
            fi
        done

        if [ "$should_keep" = true ]; then
            keep_versions+=("$version_id")
        else
            remove_versions+=("$version_id")
        fi
    done

    keep_count=${#keep_versions[@]}
    remove_count=${#remove_versions[@]}

    echo "  Found ${#version_details[@]} total image versions"
    if [ "$MODE" = "unsupported" ]; then
        echo "  Found ${#gdal_versions[@]} unique GDAL versions"
        supported_count=${#keep_gdal_vers[@]}
        unsupported_count=$((${#gdal_versions[@]} - supported_count))
        echo "  Supported versions to keep: $supported_count"
        echo "  Unsupported versions to remove: $unsupported_count"
    else
        echo "  Found ${#gdal_versions[@]} unique GDAL versions"
        echo "  Keeping $KEEP_VERSIONS most recent GDAL versions ($keep_count images total)"
        echo "  Would remove $remove_count older images from older GDAL versions"
    fi

    # Show GDAL versions to keep
    if [ ${#keep_gdal_vers[@]} -gt 0 ]; then
        echo "  [PIN] GDAL versions to keep:"
        for gdal_ver in "${keep_gdal_vers[@]}"; do
            echo "    [OK] GDAL $gdal_ver"
        done
    fi

    # Show versions to keep with details
    if [ $keep_count -gt 0 ]; then
        echo "  [PKG] Images to keep:"
        for version_id in "${keep_versions[@]}"; do
            details="${version_details[$version_id]}"
            created_at=$(echo "$details" | cut -d'|' -f1)
            tags=$(echo "$details" | cut -d'|' -f2-)
            gdal_ver=$(echo "$details" | cut -d'|' -f3)
            tag_list=$(echo "$tags" | tr ' ' ',' | sed 's/,$//')
            [ -z "$tag_list" ] && tag_list="untagged"
            echo "    [OK] GDAL $gdal_ver: $tag_list (created: $created_at)"
        done
    fi

    # Show versions to remove
    if [ $remove_count -gt 0 ]; then
        echo "  [REMOVE] Images to remove:"
        for version_id in "${remove_versions[@]}"; do
            details="${version_details[$version_id]}"
            created_at=$(echo "$details" | cut -d'|' -f1)
            tags=$(echo "$details" | cut -d'|' -f2-)
            gdal_ver=$(echo "$details" | cut -d'|' -f3)
            tag_list=$(echo "$tags" | tr ' ' ',' | sed 's/,$//')
            [ -z "$tag_list" ] && tag_list="untagged"
            echo "    [DELETE] GDAL $gdal_ver: $tag_list (created: $created_at)"
        done

        # Confirm removal unless forced or dry run
        if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
            echo
            read -p "  Remove these $remove_count old images from older GDAL versions? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "  [SKIP]  Skipping removal for $package"
                continue
            fi
        fi

        # Perform removal
        if [ "$DRY_RUN" = false ]; then
            echo "  [ACTION] Removing old versions..."
            removed=0
            for version_id in $remove_versions; do
                if gh api -X DELETE "/user/packages/container/$package/versions/$version_id" 2>/dev/null; then
                    echo "    [OK] Successfully removed version $version_id"
                    ((removed++))
                    ((total_removed++))
                else
                    echo "    [FAIL] Failed to remove version $version_id"
                fi
            done
            echo "  [DONE] Removed $removed out of $remove_count images from older GDAL versions"
        else
            echo "  [SKIP]  Skipping removal (dry run)"
        fi
    else
        echo "  [OK] No old versions to remove"
    fi

    echo
done <<< "$packages"

# Summary
echo "[SUMMARY] Cleanup Summary:"
if [ "$DRY_RUN" = true ]; then
    echo "  - Analyzed all packages"
    echo "  - No images were actually removed (dry run)"
    echo "  - Review the output above to see what would be cleaned up"
else
    echo "  - Analyzed all packages"
    echo "  - Successfully removed $total_removed old image versions"
    if [ "$MODE" = "unsupported" ]; then
        echo "  - Removed all images for versions not in $VERSIONS_FILE"
    else
        echo "  - Kept the $KEEP_VERSIONS most recent GDAL versions and all their associated images"
    fi
fi