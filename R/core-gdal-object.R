#' Dynamic GDAL API Object
#'
#' @description
#' The `gdal.alg` object is the main entry point for the dynamic GDAL API.
#' It provides hierarchical access to all GDAL commands via R6-based
#' nested objects.
#'
#' @details
#' The `gdal.alg` object is created automatically when gdalcli is loaded
#' (requires GDAL >= 3.11 and gdalraster package). It mirrors the structure
#' of Python's `gdal.alg` module.
#'
#' ## Usage
#'
#' Access commands using the `$` operator at multiple levels:
#'
#' ```r
#' # Top level: access command groups
#' gdal.alg$raster
#' gdal.alg$vector
#' gdal.alg$mdim
#'
#' # Second level: access specific commands
#' gdal.alg$raster$info
#' gdal.alg$raster$convert
#' gdal.alg$vector$translate
#'
#' # Call commands to create lazy-evaluated jobs
#' job <- gdal.alg$raster$info(input = "data.tif")
#' result <- gdal_job_run(job)
#' ```
#'
#' ## Command Groups
#'
#' Available command groups depend on your GDAL installation:
#' - **raster**: Raster file operations (info, convert, translate, etc.)
#' - **vector**: Vector file operations (convert, translate, info, etc.)
#' - **mdim**: Multidimensional data operations
#' - **vsi**: Virtual File System operations
#' - **driver**: Driver-specific utilities
#'
#' ## Lazy Evaluation
#'
#' All commands return `gdal_job` objects that are executed lazily.
#' Compose jobs using pipe (`|>`) and helper functions:
#'
#' ```r
#' gdal.alg$raster$convert(input = "in.tif", output = "out.tif") |>
#'   gdal_with_co("COMPRESS=LZW") |>
#'   gdal_with_config("GDAL_NUM_THREADS=4") |>
#'   gdal_run()
#' ```
#'
#' ## IDE Autocompletion
#'
#' The `gdal.alg` object supports full IDE autocompletion in:
#' - RStudio
#' - VSCode with R extension
#' - Emacs with ESS
#'
#' Type `gdal.alg$` and press Tab to see available groups,
#' then type `gdal.alg$raster$` and press Tab for available commands.
#'
#' @format
#' An [R6::R6Class] object with reference semantics.
#'
#' @seealso
#'   [gdal_job_run()], [gdal_with_co()], [gdal_with_config()],
#'   [new_gdal_job()]
#'
#' @examples
#' \dontrun{
#'   # Check available command groups
#'   gdal.alg
#'
#'   # Create a raster info job
#'   job <- gdal.alg()$raster$info(input = "data.tif")
#'
#'   # Execute with gdal_run
#'   result <- gdal_job_run(job)
#' }
#'
#' @export
gdal.alg <- function() {
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    stop("gdalraster package required for dynamic API. Install with: install.packages('gdalraster')")
  }

  # Create a new instance each time (disk caching makes this fast)
  GdalApi()
}
