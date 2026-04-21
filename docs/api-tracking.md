# API Tracking

## Workflow Requirements

API change tracking compares `inst/GDAL_API_*.json` (current) with previous version in git.

**Prerequisites**:
- Previous version APIs in git (`release/gdal-X.Y` branch)
- Current GDAL version installed locally (or in Docker)
- `generate_gdal_api.R` run with target version

## Usage

```bash
Rscript build/api_change_tracking.R 3.11.4 3.12.3 \
  --release-version 0.6.0 \
  --release-notes RELEASE_NOTES.md \
  --log-changes inst/CHANGELOG-API.jsonl
```

## Scripts

- `build/generate_gdal_api.R` - Generate APIs from GDAL
- `build/compare_gdal_api.R` - Compare versions from git and inst/
- `build/generate_release_notes.R` - Format release notes
- `build/api_change_tracking.R` - Orchestrate all three

## Change Log

Appended to `inst/CHANGELOG-API.jsonl` (JSONL format, one entry per line):

```json
{"timestamp":"2026-04-16T04:20:03Z","previous_version":"3.11.4","current_version":"3.12.3","package_version":"0.6.0","new_commands_count":11,"removed_commands_count":1,"modified_commands_count":0,"git_sha":"cf6243767...","release_branch":"release/gdal-3.12"}
```

### Query Examples

```bash
# View all changes
cat inst/CHANGELOG-API.jsonl | jq '.'

# Get changes for specific version
cat inst/CHANGELOG-API.jsonl | jq 'select(.current_version == "3.12.3")'

# Count new commands
cat inst/CHANGELOG-API.jsonl | jq '.new_commands_count'
```

## Known Limitations

- **Patch releases** (3.12.0 → 3.12.1): Works cleanly, both versions likely available
- **Cross-minor versions**: Requires Docker or pre-generated APIs
- **First release for new version**: No previous version to compare
