#' Infer command intent for a GDAL job.
#'
#' This function maps commands to an update intent model:
#' - "MUTATIVE": Commands that modify existing data (e.g., gdal_raster_edit)
#' - "DESTRUCTIVE": Commands that overwrite or delete data
#' - "SAFE": Normal pipeline operations with distinct inputs/outputs (default)
#' - "READ_ONLY": Non-mutating analysis operations
#'
#' @keywords internal
#'
#' @param func_name Name of the R function (e.g., "gdal_raster_clip").
#' @param merged_args Named list of merged function arguments.
#' @param intent_mapping Optional list containing update intent rules for this command.
#'   Expected fields: `opens_for_update` (logical).
#'
#' @return A list with:
#'   - `opens_for_update`: Logical indicating if the command modifies input data.
#'   - `intent`: Character string describing the update intent ("MUTATIVE", "DESTRUCTIVE", "SAFE", or "READ_ONLY").
#'
#' @details
#' The function infers intent by checking:
#' 1. The command's known intent from the mapping (most reliable)
#' 2. Argument-based overrides ("update" = TRUE makes it MUTATIVE, "overwrite" = FALSE makes it SAFE)
#' 3. Defaults to "SAFE" for unknown commands
#'
#' @export
infer_command_intent <- function(func_name, merged_args, intent_mapping = NULL) {
  # Default: read-only, does not modify input
  opens_for_update <- FALSE
  intent <- "SAFE"
  
  # Check if intent mapping specifies this command opens for update
  if (!is.null(intent_mapping) && is.list(intent_mapping)) {
    if (isTRUE(intent_mapping$opens_for_update)) {
      opens_for_update <- TRUE
      intent <- "MUTATIVE"
    }
  }
  
  # Argument-based overrides (applied after mapping to allow flexibility)
  if (!is.null(merged_args) && is.list(merged_args)) {
    # If "update" argument is TRUE, this is explicitly a mutative operation
    if (isTRUE(merged_args$update)) {
      opens_for_update <- TRUE
      intent <- "MUTATIVE"
    }
    
    # If "overwrite" argument is TRUE and opening for update was set, escalate to DESTRUCTIVE
    if (isTRUE(merged_args$overwrite) && opens_for_update) {
      intent <- "DESTRUCTIVE"
    }
    
    # If "overwrite" is FALSE, it's definitely SAFE (not destructive)
    if (isFALSE(merged_args$overwrite)) {
      opens_for_update <- FALSE
      intent <- "SAFE"
    }
  }
  
  return(list(
    opens_for_update = opens_for_update,
    intent = intent
  ))
}
