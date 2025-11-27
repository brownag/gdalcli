#!/usr/bin/env Rscript

# Setup script to clone/update local GDAL repo for RST example fetching
# Uses the detected GDAL version to checkout the appropriate tag

library(processx)

setup_gdal_repo <- function(gdal_version = NULL, repo_dir = "build/gdal_repo") {
  
  cat("Setting up local GDAL repository for RST file access...\n")
  
  # Determine the version tag to checkout
  if (!is.null(gdal_version) && !is.null(gdal_version$full)) {
    version_tag <- sprintf("v%s", gdal_version$full)
  } else {
    version_tag <- "master"
  }
  
  cat(sprintf("Target version: %s\n", version_tag))
  
  # Check if repo exists
  if (!dir.exists(repo_dir)) {
    cat(sprintf("Cloning GDAL repository to %s...\n", repo_dir))
    cat("(This may take a few minutes on first run)\n")
    
    tryCatch(
      {
        result <- processx::run(
          "git",
          c("clone", "--depth", "1", "--branch", version_tag,
            "https://github.com/OSGeo/gdal.git", repo_dir),
          timeout = 600
        )
        cat("[OK] Repository cloned successfully\n")
        return(repo_dir)
      },
      error = function(e) {
        # Fallback: clone without specifying branch, then checkout
        cat(sprintf("[WARN] Failed to clone with specific branch: %s\n", e$message))
        cat("Trying shallow clone of all branches...\n")
        
        tryCatch(
          {
            processx::run(
              "git",
              c("clone", "--depth", "1",
                "https://github.com/OSGeo/gdal.git", repo_dir),
              timeout = 600
            )
            
            # Change to repo and checkout tag
            old_wd <- getwd()
            on.exit(setwd(old_wd))
            setwd(repo_dir)
            
            processx::run("git", c("fetch", "--depth=1", "origin", sprintf("refs/tags/%s:refs/tags/%s", version_tag, version_tag)))
            processx::run("git", c("checkout", version_tag))
            
            cat("[OK] Repository cloned and checked out\n")
            return(repo_dir)
          },
          error = function(e2) {
            cat(sprintf("[ERROR] Failed to setup repository: %s\n", e2$message))
            return(NULL)
          }
        )
      }
    )
  } else {
    cat(sprintf("Repository already exists at %s\n", repo_dir))
    
    # Update to the correct version if needed
    tryCatch(
      {
        old_wd <- getwd()
        on.exit(setwd(old_wd))
        setwd(repo_dir)
        
        # Check current branch/tag
        result <- processx::run("git", c("rev-parse", "--abbrev-ref", "HEAD"), stdout = "|")
        current <- trimws(result$stdout)
        
        if (current != version_tag) {
          cat(sprintf("Checking out version %s (currently on %s)...\n", version_tag, current))
          processx::run("git", c("fetch", "--depth=1", "origin", sprintf("refs/tags/%s:refs/tags/%s", version_tag, version_tag)))
          processx::run("git", c("checkout", version_tag))
          cat("[OK] Checked out version\n")
        }
        
        return(repo_dir)
      },
      error = function(e) {
        cat(sprintf("[WARN] Could not update repository: %s\n", e$message))
        return(repo_dir)  # Still use it even if update failed
      }
    )
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
