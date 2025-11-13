#' Compose GDAL Virtual File System (VSI) URLs
#'
#' @description
#' `vsi_url()` composes GDAL Virtual File System (VSI) URLs across 30+ handlers
#' including cloud storage (S3, GCS, Azure, OSS, Swift), archive formats (ZIP, TAR, 7z, RAR),
#' and utility handlers (memory, subfile, encryption).
#'
#' The function supports recursive composition of VSI paths, enabling complex nested
#' scenarios such as accessing a shapefile within a ZIP archive stored on an S3 bucket.
#' Authentication is decoupled from URL composition and managed through environment
#' variables via [set_gdal_auth()].
#'
#' @param handler Character string identifying the VSI handler prefix (e.g., "vsis3",
#'   "vsizip", "vsiaz"). Dispatches to the corresponding handler function.
#'   Supported handlers are documented via their individual functions (see **See Also** section).
#' @param ... Handler-specific arguments. Passed through to the corresponding `vsi*_url()` function.
#' @param streaming Logical. If `TRUE`, appends `_streaming` to the handler prefix
#'   (e.g., `/vsis3_streaming/` instead of `/vsis3/`). Streaming handlers are
#'   optimized for sequential-only access and should be used only when random-access
#'   efficiency is not required. Default is `FALSE` (random-access, recommended for
#'   Cloud Optimized GeoTIFF and similar formats).
#' @param validate Logical. If `TRUE`, performs strict validation on path components:
#'   checks for empty strings, illegal characters, and other constraints. Default is
#'   `FALSE`, which preserves maximum flexibility for composing URLs to non-existent,
#'   remote, or future paths.
#'
#' @return
#' A character string representing the composed VSI path, suitable for use with
#' GDAL-aware functions (e.g., `sf::read_sf()`, `stars::read_stars()`, `raster::brick()`).
#'
#' @details
#'
#' `vsi_url()` dispatches to handler-specific functions based on the `handler` parameter:
#'
#' **Path-based handlers:** [vsis3_url()], [vsigs_url()], [vsiaz_url()], [vsiadls_url()],
#' [vsioss_url()], [vsiswift_url()], [vsicurl_url()], [vsigzip_url()], [vsimem_url()],
#' [vsihdfs_url()], [vsiwebhdfs_url()]
#'
#' **Wrapper/archive handlers:** [vsizip_url()], [vsitar_url()], [vsi7z_url()], [vsirar_url()],
#' [vsisubfile_url()], [vsicrypt_url()], [vsicached_url()], [vsisparse_url()]
#'
#' @section GDAL Version Support:
#'
#' **Minimum GDAL version: 3.6.1** (recommended for production use).
#'
#' Handler availability across GDAL versions:
#'
#' Cloud handlers (S3, GCS, Azure, OSS, Swift) are available across all GDAL 3.x versions.
#' Archive handlers (ZIP, TAR, GZip) are available across all versions.
#' Archive handlers (7z, RAR) require GDAL 3.7.0 or later (with libarchive).
#' Utility handlers (mem, subfile, crypt, cached, sparse) are available across all versions.
#' Network handlers (curl, HDFS, WebHDFS) are available across all versions.
#'
#' @section Authentication:
#'
#' Credentials for cloud storage handlers must be configured via environment variables.
#' Use [set_gdal_auth()] to set these variables securely:
#'
#' ```r
#' # Set AWS S3 credentials
#' set_gdal_auth("s3", access_key_id = "...", secret_access_key = "...")
#'
#' # Set Azure Blob Storage credentials
#' set_gdal_auth("azure", connection_string = "...")
#'
#' # Then compose and use the URL
#' url <- vsi_url("vsis3", bucket = "my-bucket", key = "path/to/file.tif")
#' ```
#'
#' @section Performance Considerations:
#'
#' - **Random-access (default)**: Use `streaming = FALSE` (default) for formats like
#'   Cloud Optimized GeoTIFF (COG), which benefit from efficient HTTP Range requests
#'   to read small data windows.
#' - **Streaming**: Use `streaming = TRUE` only for sequential-only workflows (e.g.,
#'   reading an entire compressed file from start to finish). Streaming through remote
#'   data can be slower due to lack of seek efficiency.
#'
#' @references
#' - Official GDAL VSI Documentation: \url{https://gdal.org/user/virtual_file_systems.html}
#' - GDAL Release Notes: \url{https://github.com/OSGeo/gdal/blob/master/NEWS.md}
#' - RFC: GDAL Virtual File Systems: \url{https://gdal.org/development/rfc/rfc25.html}
#'
#' @examples
#' # Public Sentinel-2 data on AWS:
#' vsi_url("vsis3",
#'   bucket = "sentinel-pds",
#'   key = "tiles/10/S/DG/2015/12/7/0/B01.jp2"
#' )
#'
#' # Simple local ZIP:
#' vsi_url("vsizip", archive_path = "data.zip", file_in_archive = "layer.shp")
#'
#' @seealso
#' [vsis3_url()], [vsigs_url()], [vsiaz_url()], [vsiadls_url()], [vsioss_url()],
#' [vsiswift_url()], [vsicurl_url()], [vsigzip_url()], [vsimem_url()], [vsihdfs_url()],
#' [vsiwebhdfs_url()], [vsizip_url()], [vsitar_url()], [vsi7z_url()], [vsirar_url()],
#' [vsisubfile_url()], [vsicrypt_url()], [vsicached_url()], [vsisparse_url()]
#'
#' @export
vsi_url <- function(handler, ..., streaming = FALSE, validate = FALSE) {
  # Dispatch to appropriate internal function based on handler
  switch(handler,
    "vsis3" = vsis3_url(..., streaming = streaming, validate = validate),
    "vsigs" = vsigs_url(..., streaming = streaming, validate = validate),
    "vsiaz" = vsiaz_url(..., streaming = streaming, validate = validate),
    "vsiadls" = vsiadls_url(..., streaming = streaming, validate = validate),
    "vsioss" = vsioss_url(..., streaming = streaming, validate = validate),
    "vsiswift" = vsiswift_url(..., streaming = streaming, validate = validate),
    "vsicurl" = vsicurl_url(..., streaming = streaming, validate = validate),
    "vsigzip" = vsigzip_url(..., streaming = streaming, validate = validate),
    "vsimem" = vsimem_url(..., streaming = streaming, validate = validate),
    "vsihdfs" = vsihdfs_url(..., streaming = streaming, validate = validate),
    "vsiwebhdfs" = vsiwebhdfs_url(..., streaming = streaming, validate = validate),
    "vsizip" = vsizip_url(..., streaming = streaming, validate = validate),
    "vsitar" = vsitar_url(..., streaming = streaming, validate = validate),
    "vsi7z" = vsi7z_url(..., streaming = streaming, validate = validate),
    "vsirar" = vsirar_url(..., streaming = streaming, validate = validate),
    "vsisubfile" = vsisubfile_url(..., streaming = streaming, validate = validate),
    "vsicrypt" = vsicrypt_url(..., streaming = streaming, validate = validate),
    "vsicached" = vsicached_url(..., streaming = streaming, validate = validate),
    "vsisparse" = vsisparse_url(..., streaming = streaming, validate = validate),
    rlang::abort(
      c(
        sprintf("No handler available for '%s'.", handler),
        "i" = "See ?vsi_url for supported handlers.",
        "!" = sprintf("Did you mean one of: vsis3, vsigs, vsiaz, vsizip, vsitar, vsicurl, ...?")
      ),
      class = "gdalcli_unsupported_handler"
    )
  )
}


#' Helper: Internal documentation generator for available VSI methods
#'
#' @keywords internal
.methods_vsi_url <- function() {
  # List all available methods for inclusion in roxygen2 documentation
  methods <- c(
    "Path-based handlers:",
    "- vsis3: AWS S3 and S3-compatible storage",
    "- vsigs: Google Cloud Storage",
    "- vsiaz: Azure Blob Storage",
    "- vsiadls: Azure Data Lake Storage Gen2",
    "- vsioss: Alibaba Cloud OSS",
    "- vsiswift: OpenStack Swift",
    "- vsicurl: HTTP, HTTPS, FTP (generic network)",
    "- vsigzip: GZip-compressed files",
    "- vsimem: In-memory files",
    "- vsihdfs: Hadoop HDFS (native protocol)",
    "- vsiwebhdfs: Hadoop WebHDFS (REST API)",
    "",
    "Archive/wrapper handlers:",
    "- vsizip: ZIP, KMZ, ODS, XLSX archives",
    "- vsitar: TAR, TGZ, TAR.GZ archives",
    "- vsi7z: 7z archives (GDAL \u2265 3.7.0)",
    "- vsirar: RAR archives (GDAL \u2265 3.7.0)",
    "- vsisubfile: Byte range within a file",
    "- vsicrypt: Encrypted files",
    "- vsicached: Cached file wrapper",
    "- vsisparse: Sparse file wrapper",
    "",
    "Each handler can use streaming=TRUE for streaming variants (e.g., vsis3_streaming)"
  )
  paste(methods, collapse = "\n")
}
