#' Package Load Hook
#'
#' @description
#' Minimal onLoad hook. The gdalcli package uses a static API of pre-generated
#' functions for a specific GDAL version. No runtime API generation occurs.
#'
#' @keywords internal

.onLoad <- function(libname, pkgname) {
  # Static API only - no dynamic initialization needed
  invisible(NULL)
}
