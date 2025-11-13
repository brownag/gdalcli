#' IDE Autocompletion for Dynamic GDAL API
#'
#' @description
#' S3 methods that enable IDE autocompletion for the dynamic GDAL API.
#' These methods are called by RStudio, VSCode, and Emacs to provide
#' tab-completion suggestions when typing `gdal.alg$` or `gdal.alg$raster$`.
#'
#' @details
#' The `.DollarNames` S3 generic is part of the R autocompletion system.
#' We implement methods for both GdalApi and GdalApiSub to enable
#' nested autocompletion at all levels.
#'
#' **Important:** We avoid calling `NextMethod()` to work around a known
#' RStudio bug with R6 method dispatch in autocompletion context.
#'
#' @importFrom utils .DollarNames
#'
#' @keywords internal

#' @export
#' @rdname dollar-names
.DollarNames.GdalApi <- function(x, pattern = "") {
  # Get all public fields and methods that aren't internal
  all_names <- names(x)

  # Filter to exclude internal fields (those starting with .)
  public_names <- setdiff(all_names, c("gdal_version", "cache_file"))

  # Filter by pattern if provided
  if (nzchar(pattern)) {
    public_names <- public_names[startsWith(public_names, pattern)]
  }

  sort(public_names)
}

#' @export
#' @rdname dollar-names
.DollarNames.GdalApiSub <- function(x, pattern = "") {
  # Get all subcommands in this group
  all_names <- x$get_subcommands()

  # Filter by pattern if provided
  if (nzchar(pattern)) {
    all_names <- all_names[startsWith(all_names, pattern)]
  }

  sort(all_names)
}
