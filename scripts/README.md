# GDAL API Research Scripts

Research and exploration utilities for investigating GDAL API structure and argument patterns. These scripts support investigation into the 3 pending enhancements identified in RESEARCH_PROMPTS.md.

## analyze_patterns.R

Analyzes GDAL API endpoints to identify argument patterns and understand how parameters are structured across commands.

**Usage:**
```bash
Rscript scripts/analyze_patterns.R              # Analyze all 'gdal' commands
Rscript scripts/analyze_patterns.R gdal vector  # Analyze specific commands
```

**Output:**
- Lists composite arguments (fixed-count multi-value parameters)
- Lists repeatable arguments (variable-count multi-value parameters)
- Shows which endpoints use each pattern
- Statistics on total endpoints analyzed

**Useful for researching:**
- [setVectorArgsFromObject()](../RESEARCH_PROMPTS.md#2-implement-vector-specific-optimization-setvectorargsfromobject) - Understanding vector workflow argument patterns
- [getExplicitlySetArgs()](../RESEARCH_PROMPTS.md#1-enhance-debugging-with-getexplicitlysetargs) - Identifying which arguments are explicitly set vs. defaulted

## inspect_endpoint.R

Examines a specific GDAL endpoint in detail to understand its input/output argument structure.

**Usage:**
```bash
Rscript scripts/inspect_endpoint.R "raster.*clip"        # Find endpoints matching pattern
Rscript scripts/inspect_endpoint.R "vector.*buffer"      # Multiple matches show all
Rscript scripts/inspect_endpoint.R "gdal_raster_info"    # Exact endpoint name
```

**Output:**
- Input arguments with min/max counts
- Input/output arguments with directionality flags
- Formatted for easy comparison across endpoints

**Useful for researching:**
- [GDALG Format Driver](../RESEARCH_PROMPTS.md#3-leverage-gdalg-format-driver-for-gdal-312-native-serialization) - Understanding endpoint capabilities and argument flow
- All three research topics - Analyzing specific endpoint structures during investigation

## Integration with Research

Both scripts source `build/generate_gdal_api.R` and use `crawl_gdal_api()` to discover GDAL endpoints dynamically from the GDAL CLI. This ensures analysis stays current with installed GDAL version.

Use these tools to:
- Validate findings from the research prompts
- Test hypotheses about API structure
- Generate examples for documentation
- Identify edge cases and patterns
