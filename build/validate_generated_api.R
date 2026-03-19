#!/usr/bin/env Rscript

# Validation script for generated GDAL API wrappers
# Checks:
# 1. All generated files exist in R/ directory
# 2. File headers contain version metadata
# 3. Examples follow proper formatting (dontrun wrapping)
# 4. No "Phase X:" comments in generated files
# 5. Documentation URLs are version-aware

sep_line <- paste(rep("=", 70), collapse = "")
cat(sep_line, "\n", sep = "")
cat("Generated API Validation Report\n")
cat(sep_line, "\n\n", sep = "")

# Get list of generated functions
generated_r_files <- list.files("R", pattern = "^gdal_.*\\.R$", full.names = TRUE)

cat(sprintf("Found %d generated R function files\n\n", length(generated_r_files)))

# Validation statistics
validation_stats <- list(
  total_files = length(generated_r_files),
  with_version_metadata = 0,
  with_dontrun_wrapping = 0,
  with_phase_comments = 0,
  with_version_aware_urls = 0,
  issues = character()
)

# Check each generated file
for (file in generated_r_files) {
  filename <- basename(file)
  content <- readLines(file, warn = FALSE)

  # Check 1: Version metadata in header
  has_version_metadata <- any(grepl("Generated for GDAL", content[1:10]))
  has_generation_date <- any(grepl("Generation date:", content[1:10]))

  if (has_version_metadata && has_generation_date) {
    validation_stats$with_version_metadata <- validation_stats$with_version_metadata + 1
  } else {
    validation_stats$issues <- c(validation_stats$issues,
      sprintf("  [MISSING_METADATA] %s: No version metadata in header", filename))
  }

  # Check 2: dontrun wrapping in examples
  has_dontrun <- any(grepl("\\\\dontrun", content))
  if (has_dontrun) {
    validation_stats$with_dontrun_wrapping <- validation_stats$with_dontrun_wrapping + 1
  } else {
    validation_stats$issues <- c(validation_stats$issues,
      sprintf("  [NO_DONTRUN] %s: No \\dontrun wrapping in examples", filename))
  }

  # Check 3: No Phase comments
  has_phase_comments <- any(grepl("Phase [0-9]:", content))
  if (has_phase_comments) {
    validation_stats$with_phase_comments <- validation_stats$with_phase_comments + 1
    validation_stats$issues <- c(validation_stats$issues,
      sprintf("  [PHASE_COMMENT] %s: Contains 'Phase X:' comments", filename))
  }

  # Check 4: Version-aware URLs
  has_version_urls <- any(grepl("gdal.org/en/[0-9]+\\.[0-9]+", content))
  if (has_version_urls) {
    validation_stats$with_version_aware_urls <- validation_stats$with_version_aware_urls + 1
  }
}

# Print summary
cat("Validation Results:\n")
cat(sprintf("  [+] Files with version metadata:    %3d/%d\n",
  validation_stats$with_version_metadata, validation_stats$total_files))
cat(sprintf("  [+] Files with dontrun wrapping:   %3d/%d\n",
  validation_stats$with_dontrun_wrapping, validation_stats$total_files))
cat(sprintf("  [+] Files with version-aware URLs: %3d/%d\n",
  validation_stats$with_version_aware_urls, validation_stats$total_files))
cat(sprintf("  [-] Files with Phase comments:     %3d/%d\n",
  validation_stats$with_phase_comments, validation_stats$total_files))

# Print issues if any
if (length(validation_stats$issues) > 0) {
  cat("\nIssues Found:\n")
  for (issue in validation_stats$issues) {
    cat(issue, "\n")
  }
} else {
  cat("\nNo issues found!\n")
}

# Overall status
cat("\n")
cat(sep_line, "\n", sep = "")
success <- validation_stats$with_phase_comments == 0 &&
           validation_stats$with_version_metadata == validation_stats$total_files &&
           validation_stats$with_dontrun_wrapping == validation_stats$total_files

if (success) {
  cat("[+] Validation PASSED\n")
} else {
  cat("[-] Validation FAILED\n")
  quit(status = 1)
}
cat(sep_line, "\n", sep = "")
