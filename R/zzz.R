#' Package Load Hook
#'
#' @description
#' Package initialization hook. Loads RFC 104 step name mappings and initializes
#' package configuration.
#'
#' @keywords internal
#' @noRd

.onLoad <- function(libname, pkgname) {
  # Load RFC 104 step name mappings from auto-generated JSON
  .load_step_mappings()
}
