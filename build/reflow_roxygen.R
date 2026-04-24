#!/usr/bin/env Rscript
#
# Reflow roxygen comments in R files to maintain consistent formatting
# This script wraps long roxygen comment lines to a maximum width
#

# Get list of R files in the R directory
r_files <- list.files(
  path = "R",
  pattern = "\\.R$",
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(r_files) == 0) {
  cat("[WARN] No R files found in R/ directory\n")
  q(status = 1)
}

cat(sprintf("[*] Found %d R files to process\n", length(r_files)))

# Configuration
MAX_WIDTH <- 80

#' Reflow roxygen comment lines in content
#' Wraps long lines by breaking at word boundaries while preserving structure
#'
#' @param content Text content to reflow (without #' prefix)
#' @param max_width Maximum line width (including prefix)
#'
#' @return Character vector of reflowed lines (with #' prefix)
reflow_text <- function(content, max_width = MAX_WIDTH) {
  if (!nzchar(content)) return("#'")
  
  # Don't reflow if the content has special structure (code blocks, lists with bullets)
  if (grepl("^\\s*-\\s", content) || grepl("^\\s*\\*\\s", content) || grepl("^\\s*[0-9]+\\.", content)) {
    return(paste0("#' ", content))
  }
  
  # Available width for content (accounting for "#' " prefix which is 3 chars)
  available_width <- max_width - 3
  
  # Split into words
  words <- unlist(strsplit(trimws(content), "\\s+"))
  
  lines <- character(0)
  current_line <- ""
  
  for (word in words) {
    # Check if adding this word would exceed max width
    test_line <- if (nzchar(current_line)) {
      paste(current_line, word)
    } else {
      word
    }
    
    if (nchar(test_line) <= available_width) {
      current_line <- test_line
    } else {
      # Save current line and start new one
      if (nzchar(current_line)) {
        lines <- c(lines, paste0("#' ", current_line))
      }
      current_line <- word
    }
  }
  
  # Add any remaining content
  if (nzchar(current_line)) {
    lines <- c(lines, paste0("#' ", current_line))
  }
  
  return(lines)
}

#' Process a single R file and reflow its roxygen comments
#'
#' @param filepath Path to R file
#'
#' @return Number of roxygen lines modified
process_file <- function(filepath) {
  tryCatch({
    lines <- readLines(filepath, warn = FALSE)
    result_lines <- character(0)
    modifications <- 0
    i <- 1
    in_description <- FALSE
    
    while (i <= length(lines)) {
      line <- lines[i]
      
      # Track if we're in a @description section
      if (grepl("^#' @description", line)) {
        in_description <- TRUE
        result_lines <- c(result_lines, line)
        i <- i + 1
        next
      }
      
      # Check if we've exited description (new tag)
      if (in_description && grepl("^#' @", line)) {
        in_description <- FALSE
      }
      
      # Only reflow lines in @description sections
      if (in_description && grepl("^#' ", line) && !grepl("^#' @", line)) {
        # This is a description continuation line
        if (nchar(line) > MAX_WIDTH) {
          # Line is too long, reflow it
          content <- sub("^#' ?", "", line)
          
          # Don't reflow if it contains code markers or special content
          if (!grepl("`|\\[|\\]|\\{|\\}", content)) {
            reflowed <- reflow_text(content)
            result_lines <- c(result_lines, reflowed)
            modifications <- modifications + 1
          } else {
            # Keep code/special content as-is
            result_lines <- c(result_lines, line)
          }
        } else {
          # Line fits within width, keep as-is
          result_lines <- c(result_lines, line)
        }
      } else {
        # Non-description roxygen or non-roxygen line, keep as-is
        result_lines <- c(result_lines, line)
      }
      
      i <- i + 1
    }
    
    # Only write back if we made modifications
    if (modifications > 0) {
      writeLines(result_lines, filepath)
    }
    
    return(modifications)
  }, error = function(e) {
    cat(sprintf("  [ERROR] %s: %s\n", filepath, e$message))
    return(0)
  })
}

# Process all files
cat("[*] Reflowing roxygen comments to max width ", MAX_WIDTH, "...\n", sep = "")
modification_counts <- sapply(r_files, process_file)

total_mods <- sum(modification_counts)
files_modified <- sum(modification_counts > 0)

if (total_mods > 0) {
  cat(sprintf("[OK] Modified %d roxygen lines in %d files\n", total_mods, files_modified))
} else {
  cat("[OK] All roxygen comments already properly formatted\n")
}

cat("[OK] Roxygen reflow complete\n")
