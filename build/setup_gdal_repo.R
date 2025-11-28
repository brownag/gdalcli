#!/usr/bin/env Rscript

# Setup script to clone/update local GDAL repo for RST example fetching
# Uses the detected GDAL version to checkout the appropriate tag

library(processx)

setup_gdal_repo <- function(gdal_version = NULL, repo_dir = "build/gdal_repo") {

  cat("Setting up local GDAL repository for RST file access...\n")

  # Determine the version tag to download
  if (!is.null(gdal_version) && !is.null(gdal_version$full)) {
    version_tag <- sprintf("v%s", gdal_version$full)
    zip_url <- sprintf("https://github.com/OSGeo/gdal/archive/refs/tags/%s.zip", version_tag)
    zip_filename <- sprintf("gdal-%s.zip", version_tag)
  } else {
    version_tag <- "master"
    zip_url <- "https://github.com/OSGeo/gdal/archive/refs/heads/master.zip"
    zip_filename <- "gdal-master.zip"
  }

  cat(sprintf("Target version: %s\n", version_tag))
  cat(sprintf("Download URL: %s\n", zip_url))

  # Check if repo exists and is up to date
  if (!dir.exists(repo_dir)) {
    cat(sprintf("Downloading GDAL repository to %s...\n", repo_dir))
    cat("(This may take a few minutes on first run)\n")

    tryCatch(
      {
        # Create temp directory for download
        temp_dir <- tempdir()
        zip_path <- file.path(temp_dir, zip_filename)

        # Download the zip file
        cat(sprintf("Downloading %s...\n", zip_url))
        processx::run(
          "curl",
          c("-L", "-o", zip_path, zip_url),
          timeout = 600
        )

        # Extract the zip file
        cat("Extracting archive...\n")
        processx::run(
          "unzip",
          c("-q", zip_path, "-d", temp_dir),
          timeout = 300
        )

        # Find the extracted directory (GitHub zips have format: gdal-v3.11.4/)
        extracted_dirs <- list.dirs(temp_dir, full.names = TRUE, recursive = FALSE)
        extracted_dir <- extracted_dirs[grepl("gdal-", basename(extracted_dirs))][1]

        if (is.na(extracted_dir)) {
          stop("Could not find extracted GDAL directory")
        }

        # Move to final location
        processx::run(
          "mv",
          c(extracted_dir, repo_dir),
          timeout = 60
        )

        # Clean up temp files
        unlink(zip_path)

        cat("[OK] Repository downloaded and extracted successfully\n")
        return(repo_dir)
      },
      error = function(e) {
        cat(sprintf("[ERROR] Failed to download repository: %s\n", e$message))
        return(NULL)
      }
    )
  } else {
    cat(sprintf("Repository already exists at %s\n", repo_dir))

    # Check if we need to update (simple check: does the directory exist and have files?)
    # For now, assume existing repo is correct - could add version checking later
    cat("[OK] Using existing repository\n")
    return(repo_dir)
  }

  return(repo_dir)
}

# Helper function to get RST file from local repo
get_rst_from_local_repo <- function(command_name, repo_dir = "build/gdal_repo") {
  rst_file <- file.path(repo_dir, "doc", "source", "programs", sprintf("%s.rst", command_name))
  
  if (file.exists(rst_file)) {
    return(readLines(rst_file, warn = FALSE))
  }
  
  return(NULL)
}

# Export for use in generate_gdal_api.R
list(
  setup_gdal_repo = setup_gdal_repo,
  get_rst_from_local_repo = get_rst_from_local_repo
)
