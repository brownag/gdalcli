#' GDAL Help Text Parser
#'
#' @description
#' Functions to parse GDAL command help text and extract structured
#' function signatures including argument names, types, and defaults.
#'
#' @details
#' The parser uses regex-based extraction to identify arguments from
#' GDAL help output. It handles both positional and optional arguments,
#' with support for various argument patterns.
#'
#' @keywords internal

#' Parse GDAL Usage Text
#'
#' Main entry point for parsing GDAL command help text into structured signatures.
#'
#' @param cmd_path Character vector of command hierarchy
#' @param usage_text Raw help text from gdalraster::gdal_usage()
#'
#' @return List with elements:
#'   - `formals`: alist suitable for rlang::new_function()
#'   - `arg_info`: Data frame with parsed argument information
#'
#' @keywords internal
parse_gdal_usage <- function(cmd_path, usage_text) {
  if (is.na(usage_text) || !nzchar(usage_text)) {
    # Return basic signature with just ...
    return(list(
      formals = alist(... = ),
      arg_info = data.frame(
        name = character(0),
        type = character(0),
        required = logical(0),
        default = character(0)
      )
    ))
  }

  # Extract arguments from usage text
  arg_info <- extract_arguments_from_usage(usage_text)

  # Convert to alist for function signature
  formals <- create_alist_from_parsed(arg_info)

  list(
    formals = formals,
    arg_info = arg_info
  )
}

#' Extract Arguments from GDAL Usage Text
#'
#' Parses usage text using regex to identify arguments.
#'
#' @param usage_text Raw help text from GDAL command
#'
#' @return Data frame with columns: name, type, required, default
#'
#' @keywords internal
extract_arguments_from_usage <- function(usage_text) {
  # Initialize result data frame
  result <- data.frame(
    name = character(0),
    type = character(0),
    required = logical(0),
    default = character(0),
    stringsAsFactors = FALSE
  )

  # Pattern 1: Positional arguments in angle brackets or all caps
  # Examples: <input>, <output>, OUTPUT_FILE, SRC_DATASET
  pos_pattern <- "(?:^|\\s+)(<?(?:[A-Z_]+|[a-z_]+)>?)"
  pos_matches <- gregexpr(pos_pattern, usage_text, perl = TRUE, ignore.case = TRUE)

  # Pattern 2: Optional flags with hyphens
  # Examples: -co, --create-options, -if INPUT_FORMAT
  opt_pattern <- "(?:^|\\s+)(?:--?[a-z-]+)"
  opt_matches <- gregexpr(opt_pattern, usage_text, perl = TRUE, ignore.case = TRUE)

  # Extract positional arguments (very basic - just collect from pattern matches)
  # For now, return minimal info - the full parser would be more sophisticated
  positional <- c("input", "output", "src_dataset", "dest_dataset", "dataset")

  # Check if these appear in the usage text (case insensitive)
  for (name in positional) {
    if (grepl(name, usage_text, ignore.case = TRUE)) {
      result <- rbind(result, data.frame(
        name = name,
        type = "character",
        required = TRUE,
        default = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Extract optional flags
  optional <- c("co", "config", "if", "of", "t_srs", "s_srs", "lco")

  for (flag in optional) {
    # Look for -flag or --flag variants
    if (grepl(paste0("[-]", flag), usage_text, ignore.case = TRUE)) {
      result <- rbind(result, data.frame(
        name = flag,
        type = "character",
        required = FALSE,
        default = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Remove duplicates
  result <- result[!duplicated(result$name), , drop = FALSE]
  rownames(result) <- NULL

  result
}

#' Create alist from Parsed Arguments
#'
#' Converts parsed argument information into an alist suitable for
#' creating functions with rlang::new_function().
#'
#' @param parsed_args Data frame from extract_arguments_from_usage()
#'
#' @return An alist with argument names as keys and defaults as values
#'
#' @keywords internal
create_alist_from_parsed <- function(parsed_args) {
  # Start with ... as catch-all
  formals <- alist(... = )

  # Add arguments from parsed info
  for (i in seq_len(nrow(parsed_args))) {
    arg_name <- parsed_args$name[i]
    arg_required <- parsed_args$required[i]

    # Create a valid R identifier if needed
    arg_name <- make.names(arg_name, unique = TRUE)

    # Add to formals
    # Required arguments have no default (missing)
    # Optional arguments default to NULL
    if (arg_required) {
      formals[[arg_name]] <- rlang::missing_arg()
    } else {
      formals[[arg_name]] <- NULL
    }
  }

  formals
}

#' Check if Argument is Valid GDAL Option
#'
#' Validates if a given argument name is a recognized GDAL option.
#'
#' @param arg_name Argument name to check
#' @param known_options Character vector of known option names
#'
#' @return Logical indicating if argument is valid
#'
#' @keywords internal
is_valid_gdal_option <- function(arg_name, known_options = NULL) {
  # Common GDAL options
  common_options <- c(
    "co", "config", "if", "of", "t_srs", "s_srs", "lco",
    "b", "mask", "a", "ct", "e", "te", "tr", "overwrite",
    "update", "creation_options", "layer", "f", "format"
  )

  if (!is.null(known_options)) {
    common_options <- c(common_options, known_options)
  }

  arg_name %in% common_options
}
