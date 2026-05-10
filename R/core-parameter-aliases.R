# Parameter alias and synonym handling
# Supports: (1) version-aware renames (RFC 104), (2) parameter synonyms
# Routes old parameter names (dst_crs > output_crs, dataset > input, etc.) based on GDAL version
# Normalizes synonyms (format/of > output_format, layer/input-layer > input_layer) always

#' Merge Parameter Aliases and Synonyms
#'
#' Handle parameter aliases (version-aware) and synonyms (always valid).
#' Routes old parameter names based on GDAL version; normalizes synonyms to canonical names.
#'
#' @param dots List from `...` containing potential aliases/synonyms
#' @param named_args Named parameters from function signature
#' @param gdal_version GDAL version string (optional, auto-detected if NULL)
#'
#' @return List of merged parameters with aliases and synonyms resolved
#' @keywords internal
.merge_alias_parameters <- function(dots, named_args, gdal_version = NULL) {
  # Canonical parameter names with version-aware aliases and synonyms
  canonical_params <- list(
    # CRS parameters (old names: dst_crs, t_srs, src_crs, s_srs, a_srs)
    output_crs = list(
      aliases = c("dst_crs", "t_srs"),
      old_name = "dst_crs",
      synonyms = c()
    ),
    input_crs = list(
      aliases = c("src_crs", "s_srs"),
      old_name = "src_crs",
      synonyms = c()
    ),
    override_crs = list(
      aliases = c("a_srs"),
      old_name = "a_srs",
      synonyms = c()
    ),
    # Dataset/input parameters (old name: dataset)
    input = list(
      aliases = c("dataset"),
      old_name = "dataset",
      synonyms = c()
    ),
    # Output format (synonyms only)
    output_format = list(
      aliases = c(),
      old_name = NULL,
      synonyms = c("format", "of", "output-format")
    ),
    # Layer parameters (synonyms only)
    input_layer = list(
      aliases = c(),
      old_name = NULL,
      synonyms = c("layer", "input-layer")
    ),
    output_layer = list(
      aliases = c(),
      old_name = NULL,
      synonyms = c()
    )
  )

  # Check if we're on GDAL 3.12+
  # Parameter renames (RFC 104) introduced in GDAL 3.12.0, standardized in 3.13.0
  # Backward compatibility: old names accepted in CLI, routed to new names
  is_new_version <- gdal_check_version("3.12", op = ">=")

  # Start with existing named arguments
  result <- named_args

  if (length(dots) > 0) {
    for (arg_name in names(dots)) {
      canonical_name <- arg_name
      found_mapping <- FALSE
      mapping_type <- NULL

      # Check if already canonical
      if (arg_name %in% names(canonical_params)) {
        canonical_name <- arg_name
        found_mapping <- TRUE
      } else {
        # Look for version-aware aliases or synonyms
        for (can_name in names(canonical_params)) {
          param_config <- canonical_params[[can_name]]

          if (arg_name %in% param_config$aliases) {
            canonical_name <- can_name
            found_mapping <- TRUE
            mapping_type <- "version_alias"
            break
          }

          if (arg_name %in% param_config$synonyms) {
            canonical_name <- can_name
            found_mapping <- TRUE
            mapping_type <- "synonym"
            break
          }
        }
      }

      if (found_mapping) {
        if (mapping_type == "version_alias") {
          # Route based on GDAL version
          if (is_new_version) {
            if (is.null(result[[canonical_name]])) {
              result[[canonical_name]] <- dots[[arg_name]]
            }
          } else {
            old_name <- canonical_params[[canonical_name]]$old_name
            if (!is.null(old_name) && is.null(result[[old_name]])) {
              result[[old_name]] <- dots[[arg_name]]
            }
          }
        } else if (mapping_type == "synonym") {
          # Normalize to canonical name
          if (is.null(result[[canonical_name]])) {
            result[[canonical_name]] <- dots[[arg_name]]
          }
        } else {
          # Already canonical
          if (is.null(result[[arg_name]])) {
            result[[arg_name]] <- dots[[arg_name]]
          }
        }
      } else {
        # No mapping found
        if (is.null(result[[arg_name]])) {
          result[[arg_name]] <- dots[[arg_name]]
        }
      }
    }
  }

  result
}

