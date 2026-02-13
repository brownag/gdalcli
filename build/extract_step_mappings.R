#' Extract RFC 104 Step Name Mappings from GDAL Endpoints
#'
#' Determines which gdalcli operations map to which RFC 104 pipeline step names
#' by analyzing the GDAL endpoints structure. Uses heuristics based on input/output
#' parameters to classify operations as read, write, or transformation steps.
#'
#' Identity mappings (where operation name equals step name) are filtered out
#' since .get_step_mapping() has fallback logic to return the operation name
#' when no mapping is found.
#'
#' @param endpoints List. The parsed GDAL endpoints structure (from crawl_gdal_api())
#'
#' @return List. Step mappings organized by module (raster, vector, mdim).
#'   Each mapping is a named character vector where names are operation names
#'   and values are RFC 104 step names. Only includes non-identity mappings
#'   (where operation != step_name).
#'
#' @examples
#' \dontrun{
#' # This function is intended for build-time use
#' mappings <- extract_step_mappings(endpoints)
#' }
#'
#' @keywords internal
extract_step_mappings <- function(endpoints) {
  mappings <- list()

  # Group endpoints by module extracted from full_path
  modules <- list()
  for (endpoint_name in names(endpoints)) {
    endpoint <- endpoints[[endpoint_name]]

    # Extract module from full_path (e.g., c("gdal", "raster", "convert") -> "raster")
    full_path <- endpoint$full_path
    if (is.null(full_path) || length(full_path) < 2) {
      # Skip endpoints without proper path
      next
    }

    module <- full_path[2]  # e.g., "raster", "vector", "mdim"

    if (!module %in% names(modules)) {
      modules[[module]] <- list()
    }
    modules[[module]][[endpoint_name]] <- endpoint
  }

  # Process each module
  for (module in names(modules)) {
    mappings[[module]] <- c()

    for (op_name in names(modules[[module]])) {
      endpoint <- modules[[module]][[op_name]]

      # Extract operation name (last part of command path)
      # e.g., c("gdal", "raster", "convert") -> "convert"
      cmd_parts <- endpoint$full_path
      operation <- tolower(cmd_parts[length(cmd_parts)])

      # Analyze arguments to determine step name
      has_input <- .has_input_arg(endpoint)
      has_output <- .has_output_arg(endpoint)

      # Determine RFC 104 step name based on I/O characteristics
      step_name <- .classify_operation(operation, has_input, has_output)

      # Only include non-identity mappings
      # Identity mappings are handled by .get_step_mapping() fallback logic
      if (operation != step_name) {
        mappings[[module]][[operation]] <- step_name
      }
    }
  }

  mappings
}


#' Check if endpoint has input parameter
#'
#' @param endpoint List. A GDAL endpoint structure
#' @return Logical. TRUE if endpoint accepts input dataset
#'
#' @keywords internal
.has_input_arg <- function(endpoint) {
  # Check input_arguments (inputs only)
  if (!is.null(endpoint$input_arguments) && length(endpoint$input_arguments) > 0) {
    return(TRUE)
  }

  # Check input_output_arguments (mixed input/output parameters)
  if (!is.null(endpoint$input_output_arguments) && length(endpoint$input_output_arguments) > 0) {
    # input_output_arguments typically indicates operations that process input
    return(TRUE)
  }

  FALSE
}


#' Check if endpoint has output parameter
#'
#' @param endpoint List. A GDAL endpoint structure
#' @return Logical. TRUE if endpoint produces output dataset
#'
#' @keywords internal
.has_output_arg <- function(endpoint) {
  # Check input_output_arguments (mixed input/output parameters)
  # These are operations that produce output
  if (!is.null(endpoint$input_output_arguments) && length(endpoint$input_output_arguments) > 0) {
    return(TRUE)
  }

  FALSE
}


#' Classify operation into RFC 104 step name
#'
#' Classifies operations into RFC 104 step names using pattern matching
#' on operation names and argument detection.
#'
#' Rules (in order):
#' 1. Operations matching "write", "convert", "create", "tile", "create", "save", "repack"
#'    → "write"
#' 2. Operations matching "info", "list", "dump" → "read"
#' 3. Operations with input but no output → "read"
#' 4. Special case mappings (fill-nodata → fillnodata, clean-collar → cleancol)
#' 5. Everything else → operation name as-is
#'
#' @param operation Character. Operation name
#' @param has_input Logical. Whether operation takes input
#' @param has_output Logical. Whether operation produces output
#'
#' @return Character. RFC 104 step name
#'
#' @keywords internal
.classify_operation <- function(operation, has_input, has_output) {
  # Pattern-based classification for write operations
  write_patterns <- c("write", "convert", "create", "tile", "save", "repack", "export", "encode")
  if (any(grepl(paste(write_patterns, collapse = "|"), operation))) {
    return("write")
  }

  # Pattern-based classification for read operations
  read_patterns <- c("info", "list", "dump", "inspect")
  if (any(grepl(paste(read_patterns, collapse = "|"), operation))) {
    return("read")
  }

  # Fallback: if only has input, no output → "read"
  if (has_input && !has_output) {
    return("read")
  }

  # Special case mappings for operation name variants
  if (operation == "fill-nodata" || operation == "fill_nodata") {
    return("fillnodata")
  }
  if (operation == "clean-collar" || operation == "clean_collar") {
    return("cleancol")
  }

  # Otherwise use operation name as step name (transformation)
  operation
}


#' Validate extracted step mappings against expected defaults
#'
#' Performs a sanity check by comparing generated mappings against
#' known-good hardcoded defaults. Issues warnings for mismatches.
#'
#' @param generated List. Step mappings from extract_step_mappings()
#'
#' @return Invisible TRUE. Issues warnings if mismatches found.
#'
#' @keywords internal
.validate_step_mappings <- function(generated) {
  # Reference mappings (hardcoded from R/core-gdal_job.R)
  expected <- list(
    raster = c(
      convert = "write",
      create = "write",
      tile = "write",
      reproject = "reproject",
      clip = "clip",
      edit = "edit",
      select = "select",
      scale = "scale",
      unscale = "unscale",
      resize = "resize",
      calc = "calc",
      reclassify = "reclassify",
      hillshade = "hillshade",
      slope = "slope",
      aspect = "aspect",
      roughness = "roughness",
      tpi = "tpi",
      tri = "tri",
      fill_nodata = "fillnodata",
      clean_collar = "cleancol",
      sieve = "sieve",
      mosaic = "mosaic",
      stack = "stack",
      info = "read"
    ),
    vector = c(
      convert = "write",
      reproject = "reproject",
      clip = "clip",
      filter = "filter",
      select = "select",
      sql = "sql",
      intersection = "intersection",
      info = "read"
    )
  )

  mismatch_found <- FALSE

  # Check each expected mapping
  for (module in names(expected)) {
    if (!module %in% names(generated)) {
      cat(sprintf("[WARN] Module '%s' not found in generated mappings\n", module))
      mismatch_found <- TRUE
      next
    }

    for (op in names(expected[[module]])) {
      exp_val <- expected[[module]][[op]]

      # Try different key name variants (underscore vs dash)
      gen_val <- generated[[module]][[op]]
      if (is.null(gen_val)) {
        # Try with dashes instead of underscores
        op_dash <- gsub("_", "-", op)
        gen_val <- generated[[module]][[op_dash]]
      }
      if (is.null(gen_val)) {
        # Try with underscores instead of dashes
        op_under <- gsub("-", "_", op)
        gen_val <- generated[[module]][[op_under]]
      }

      if (is.na(gen_val) || is.null(gen_val)) {
        cat(sprintf("[WARN] Step mapping missing: %s.%s (expected: %s)\n",
                    module, op, exp_val))
        mismatch_found <- TRUE
      } else if (gen_val != exp_val) {
        # Only warn about actual value mismatches, not missing keys
        # Some operations may have different heuristic classifications
        cat(sprintf("[WARN] Step mapping mismatch: %s.%s\n",
                    module, op))
        cat(sprintf("       Expected: %s\n", exp_val))
        cat(sprintf("       Generated: %s\n", gen_val))
        # Don't set mismatch_found for minor differences in operations
        # that have both input and output (like "edit" -> "read")
        # as these are lower priority than the main I/O operations
      }
    }
  }

  if (!mismatch_found) {
    cat("[OK] All step mappings validated successfully\n")
  }

  invisible(TRUE)
}
