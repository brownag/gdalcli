#' GDAL Parameter Aliases and Synonyms
#'
#' Documentation of parameter aliases and synonyms supported by gdalcli functions
#' for backward compatibility across GDAL versions.
#'
#' @details
#' All gdalcli wrapper functions support flexible parameter naming through two mechanisms:
#'
#' **Version-aware aliases**: Old GDAL parameter names (introduced before RFC 104)
#' automatically route to modern names on GDAL 3.12+, where parameter standardization
#' (RFC 104) introduced the new naming scheme. Backward compatibility is maintained
#' throughout: pass either old or new names; routing is automatic.
#'
#' Common aliases (RFC 104 - GDAL 3.12+):
#' - `dst_crs` or `t_srs` -> `output_crs` (standardized CRS destination parameter)
#' - `src_crs` or `s_srs` -> `input_crs` (standardized CRS source parameter)
#' - `dataset` -> `input` (unified input parameter naming)
#' - `a_srs` -> `override_crs` (CRS override without reprojection)
#'
#' **Parameter synonyms**: Alternative names for the same parameter that are always
#' valid, regardless of GDAL version. Useful for shorter or more familiar parameter names.
#'
#' Common synonyms:
#' - `output_format`: also accepts `format`, `of`, `output-format`
#' - `input_layer`: also accepts `layer`, `input-layer`
#'
#' Users can pass parameters using either old or new names; the system automatically
#' handles routing to the correct names for the installed GDAL version.
#'
#' @examples
#' \dontrun{
#' # All of these are equivalent across GDAL versions
#' job1 <- gdal_raster_reproject(input = "in.tif", output_crs = "EPSG:4326")
#' job2 <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:4326")  # Old name
#' job3 <- gdal_raster_reproject(input = "in.tif", t_srs = "EPSG:4326")   # Legacy gdalwarp name
#'
#' # Parameter synonyms
#' conv1 <- gdal_raster_convert(input = "in.tif", output_format = "COG")
#' conv2 <- gdal_raster_convert(input = "in.tif", format = "COG")        # Shorter
#' conv3 <- gdal_raster_convert(input = "in.tif", of = "COG")            # Abbreviation
#' }
#' @seealso [gdal_call()] for dynamic command invocation, [gdal_check_version()] for version-specific logic
#' @name gdal_parameter_aliases
NULL
