#!/usr/bin/env Rscript
# Integration Example 2: Vector Processing with Complex Metadata
# 
# This example demonstrates:
# - Creating a vector processing pipeline
# - Building and preserving complex hierarchical metadata
# - Round-trip serialization with nested structures
# - Metadata access after loading
#
# Uses built-in sample data (sample_mapunit_polygons.gpkg)

devtools::load_all()

separator <- paste(rep("=", 70), collapse = "")

cat("\n", separator, "\n", sep = "")
cat("Example 2: Vector Pipeline with Complex Metadata (Real Data)\n")
cat(separator, "\n\n", sep = "")

# Use the built-in sample vector data
sample_vector <- system.file("extdata/sample_mapunit_polygons.gpkg", package = "gdalcli")
output_dir <- tempdir()
output_vector <- file.path(output_dir, "reproject_mapunits.gpkg")

cat("1. Using sample vector data:\n")
cat("   Input:", basename(sample_vector), "\n")
cat("   Output directory:", output_dir, "\n\n")

# Create a vector processing pipeline
# Reproject to Web Mercator -> Convert to GeoPackage with updates
pipeline <- gdal_vector_reproject(
  input = sample_vector,
  output = output_vector,
  dst_crs = "EPSG:3857"  # Web Mercator
) |>
  gdal_vector_convert(
    output = file.path(output_dir, "final_mapunits.gpkg"),
    output_format = "GPKG"
  )

cat("2. Created pipeline with 2 operations:\n")
cat("   - Reproject to Web Mercator (EPSG:3857)\n")
cat("   - Convert to GeoPackage format\n\n")

# Create comprehensive metadata with nested structure
metadata <- list(
  # Project information
  project = list(
    name = "Soil Mapping Initiative",
    id = "SMI-2024-001",
    principal_investigator = "John Doe"
  ),
  # Data quality and processing metrics
  data_quality = list(
    validation_status = "approved",
    accuracy_assessment = "95%",
    source_confidence = "high",
    last_validated = as.character(Sys.Date())
  ),
  # Processing configuration
  processing = list(
    algorithm = "SSURGO-based",
    parameters = "default",
    execution_time_seconds = 45.3
  ),
  # Data lineage
  lineage = list(
    original_source = "SSURGO",
    processing_chain = "extract -> validate -> normalize",
    intermediate_datasets = 3,
    final_approval = TRUE
  ),
  # Access and usage rights
  usage = list(
    license = "CC-BY-4.0",
    citation = "Doe et al. (2024)",
    restricted = FALSE
  )
)

# Save to hybrid format
output_file <- "/tmp/vector_workflow.gdalcli.json"
cat("3. Saving vector pipeline to:", output_file, "\n\n")

tryCatch({
  gdal_save_pipeline(
    pipeline,
    path = output_file,
    name = "SSURGO Mapunit Projection",
    description = "Reproject soil mapunit polygons to Web Mercator for web mapping compatibility and convert to GeoPackage",
    custom_tags = metadata,
    verbose = TRUE
  )
  
  if (file.exists(output_file)) {
    cat("\n✓ Vector pipeline saved successfully\n\n")
    file_info <- file.info(output_file)
    cat("   File size:", round(file_info$size / 1024, 2), "KB\n\n")
  }
}, error = function(e) {
  cat("✗ Error:", conditionMessage(e), "\n")
})

# Load and verify
cat("4. Loading and verifying pipeline...\n\n")
tryCatch({
  loaded_pipeline <- gdal_load_pipeline(output_file)
  
  cat("✓ Pipeline loaded successfully\n")
  cat("   Name:", loaded_pipeline$name, "\n")
  cat("   Jobs:", length(loaded_pipeline$jobs), "\n\n")
  
  # Parse and display the saved content
  saved_json <- jsonlite::fromJSON(readLines(output_file), simplifyVector = FALSE)
  
  cat("5. Metadata Preservation Verification:\n")
  cat(paste(rep("-", 70), collapse = ""), "\n\n")
  
  # Check metadata structure
  meta <- saved_json$metadata
  cat("Standard Metadata:\n")
  cat("  Pipeline:", meta$pipeline_name, "\n")
  cat("  Created:", substr(meta$created_at, 1, 10), "\n")
  cat("  GDAL Requirement:", meta$gdal_version_required, "\n\n")
  
  # Check custom tags (nested structure)
  cat("Custom Tags (Hierarchical Structure):\n")
  tags <- meta$custom_tags
  
  cat("\n  Project Information:\n")
  for (key in names(tags$project)) {
    cat("    ", key, ":", as.character(tags$project[[key]]), "\n", sep = "")
  }
  
  cat("\n  Data Quality:\n")
  for (key in names(tags$data_quality)) {
    if (is.list(tags$data_quality[[key]])) {
      cat("    ", key, ":", length(tags$data_quality[[key]]), "items", "\n", sep = "")
    } else {
      cat("    ", key, ":", as.character(tags$data_quality[[key]]), "\n", sep = "")
    }
  }
  
  cat("\n  Processing Configuration:\n")
  for (key in names(tags$processing)) {
    cat("    ", key, ":", as.character(tags$processing[[key]]), "\n", sep = "")
  }
  
  cat("\n  Data Lineage:\n")
  for (key in names(tags$lineage)) {
    if (is.list(tags$lineage[[key]])) {
      cat("    ", key, ":", as.character(tags$lineage[[key]]), "\n", sep = "")
    } else {
      cat("    ", key, ":", as.character(tags$lineage[[key]]), "\n", sep = "")
    }
  }
  
  cat("\n  Usage Rights:\n")
  for (key in names(tags$usage)) {
    cat("    ", key, ":", as.character(tags$usage[[key]]), "\n", sep = "")
  }
  
  # Verify r_job_specs were preserved
  cat("\n\nJob Specifications (Preserved for Lossless Reconstruction):\n")
  cat("  ", length(saved_json$r_job_specs), "job specifications stored\n", sep = "")
  for (i in seq_along(saved_json$r_job_specs)) {
    job <- saved_json$r_job_specs[[i]]
    cat("  Job", i, ":", paste(job$command_path, collapse = " "), "\n")
  }
  
}, error = function(e) {
  cat("✗ Error:", conditionMessage(e), "\n")
})

cat("\n", separator, "\n", sep = "")
cat("✓ Example 2 Complete: Complex nested metadata successfully preserved\n")
cat(separator, "\n")
