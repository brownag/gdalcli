#' Dynamic GDAL API Object
#'
#' @description
#' The `gdal` object is the main entry point for the dynamic GDAL API.
#' It provides hierarchical access to all GDAL commands via R6-based
#' nested objects.
#'
#' @details
#' The `gdal` object is created automatically when gdalcli is loaded
#' (requires GDAL >= 3.11 and gdalraster package). It mirrors the structure
#' of Python's `gdal.alg` module.
#'
#' ## Usage
#'
#' Access commands using the `$` operator at multiple levels:
#'
#' ```r
#' # Top level: access command groups
#' gdal$raster
#' gdal$vector
#' gdal$mdim
#'
#' # Second level: access specific commands
#' gdal$raster$info
#' gdal$raster$convert
#' gdal$vector$translate
#'
#' # Call commands to create lazy-evaluated jobs
#' job <- gdal$raster$info(input = "data.tif")
#' result <- gdal_run(job)
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
#' gdal$raster$convert(input = "in.tif", output = "out.tif") |>
#'   gdal_with_co("COMPRESS=LZW") |>
#'   gdal_with_config("GDAL_NUM_THREADS=4") |>
#'   gdal_run()
#' ```
#'
#' ## IDE Autocompletion
#'
#' The `gdal` object supports full IDE autocompletion in:
#' - RStudio
#' - VSCode with R extension
#' - Emacs with ESS
#'
#' Type `gdal$` and press Tab to see available groups,
#' then type `gdal$raster$` and press Tab for available commands.
#'
#' @format
#' An [R6::R6Class] object with reference semantics.
#'
#' @seealso
#'   [gdal_run()], [gdal_with_co()], [gdal_with_config()],
#'   [new_gdal_job()]
#'
#' @examples
#' \dontrun{
#'   # Check available command groups
#'   gdal
#'
#'   # Create a raster info job
#'   job <- gdal$raster$info(input = "data.tif")
#'
#'   # Execute with gdal_run
#'   result <- gdal_run(job)
#' }
#'
#' @export
"gdal"
