#' Infer update intent for a GDAL command.
#'
#' @description
#' Determines whether a GDAL command opens a dataset for in-place update
#' vs. creation based on RFC 104 open_for_update semantics.
#'
#' This enables pipeline steps to be correctly classified:
#' - `TRUE`: Command opens file for in-place modification (gdal_raster_edit, etc.)
#' - `FALSE`: Command creates new dataset or reads only (default)
#'
#' @keywords internal
#'
#' @param func_name Character. Name of the R function (e.g., "gdal_raster_overview_add").
#' @param merged_args List. Merged function arguments.
#' @param update_intent_mapping List. Per-algorithm update intent rules from GDAL_INTENT_MAPPINGS.json.
#'   Expected fields:
#'   - `by_default`: Logical, default update intent
#'   - `if_any_of`: Character vector of argument names that enable update
#'   - `unless_any_of`: Character vector of argument names that disable update
#'
#' @return List with `opens_for_update` boolean field indicating update intent.
#'
#' @details
#' Update intent inference follows this logic:
#' 1. Start with default from mapping (by_default field)
#' 2. Apply if_any_of: if any listed arguments are present, enable update
#' 3. Apply unless_any_of: if any listed arguments are present, disable update
#' 4. Default to FALSE if no mapping provided
#'
#' This function implements RFC 104 open_for_update semantics for accurate
#' pipeline classification and behavior prediction.
#'
#' @export
infer_update_intent <- function(func_name, merged_args, update_intent_mapping = NULL) {
  # Default: dataset is not opened for update
  opens_for_update <- FALSE
  
  # Apply by_default rule from mapping
  if (!is.null(update_intent_mapping) && is.list(update_intent_mapping)) {
    if (isTRUE(update_intent_mapping$by_default)) {
      opens_for_update <- TRUE
    }
  }
  
  # Apply if_any_of triggers (enable update if any of these args are present)
  if (!is.null(update_intent_mapping$if_any_of)) {
    if (any(names(merged_args) %in% update_intent_mapping$if_any_of)) {
      opens_for_update <- TRUE
    }
  }
  
  # Apply unless_any_of exclusions (disable update if any of these args are present)
  if (!is.null(update_intent_mapping$unless_any_of)) {
    if (any(names(merged_args) %in% update_intent_mapping$unless_any_of)) {
      opens_for_update <- FALSE
    }
  }
  
  return(list(opens_for_update = opens_for_update))
}
