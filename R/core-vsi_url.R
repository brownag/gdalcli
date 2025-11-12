#' Compose GDAL Virtual File System (VSI) URLs
#'
#' @description
#' `vsi_url()` is an S3 generic method for composing GDAL Virtual File System
#' (VSI) URLs across 30+ handlers including cloud storage (S3, GCS, Azure, OSS, Swift),
#' archive formats (ZIP, TAR, 7z, RAR), and utility handlers (memory, subfile, encryption).
#'
#' The function supports recursive composition of VSI paths, enabling complex nested
#' scenarios such as accessing a shapefile within a ZIP archive stored on an S3 bucket.
#' Authentication is decoupled from URL composition and managed through environment
#' variables via [set_gdal_auth()].
#'
#' @param handler Character string identifying the VSI handler prefix (e.g., "vsis3",
#'   "vsizip", "vsiaz"). Dispatches to an S3 method for that handler. Supported values
#'   are listed in the **Methods** section below.
#' @param ... Handler-specific arguments passed to the corresponding S3 method.
#'   See method documentation for details (e.g., `?vsi_url.vsis3`).
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
#' @section GDAL Version Support:
#'
#' **Minimum GDAL version: 3.6.1** (recommended for production use).
#'
#' Handler availability across GDAL versions:
#'
#' | Handler Family | GDAL 3.0.0 | GDAL 3.6.1 | GDAL 3.7.0 | GDAL 3.12.0 |
#' |---|---|---|---|---|
#' | Cloud (S3, GCS, Azure, OSS, Swift) | ✓ | ✓ (mature) | ✓ | ✓ (enhanced) |
#' | Cloud streaming variants | ✓ | ✓ | ✓ | ✓ |
#' | Archive (ZIP, TAR, GZip) | ✓ | ✓ | ✓ | ✓ |
#' | Archive (7z, RAR) | — | — | ✓ (libarchive) | ✓ |
#' | Utility (mem, subfile, crypt, cached, sparse) | ✓ | ✓ | ✓ | ✓ |
#' | Network (curl, HDFS, WebHDFS) | ✓ | ✓ | ✓ | ✓ |
#'
#' @section Methods:
#'
#' This is an S3 generic, so packages can provide new implementations for new handlers.
#' Methods available in this package:
#'
#' \Sexpr[stage=render,results=rd]{gdalcli:::.methods_vsi_url()}
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
#' # Simple path-based handler: AWS S3
#' vsi_url("vsis3", bucket = "sentinel-pds", key = "tiles/10/S/DG/2015/12/7/0/B01.jp2")
#'
#' # Recursive composition: ZIP archive on S3
#' s3_zip <- vsi_url("vsis3", bucket = "my-bucket", key = "archive.zip")
#' vsi_url("vsizip", archive_path = s3_zip, file_in_archive = "data/layer.shp")
#'
#' # Multi-level nesting: TAR.GZ inside ZIP on S3
#' inner_vsi <- vsi_url("vsis3", "bucket", "archive.zip")
#' outer_vsi <- vsi_url("vsizip", inner_vsi, "nested/data.tar.gz")
#' final_vsi <- vsi_url("vsitar", outer_vsi, "file.tif")
#'
#' @export
vsi_url <- function(handler, ..., streaming = FALSE, validate = FALSE) {
  UseMethod("vsi_url", handler)
}


#' @export
#' @rdname vsi_url
vsi_url.default <- function(handler, ..., streaming = FALSE, validate = FALSE) {
  rlang::abort(
    c(
      sprintf("No S3 method available for handler '%s'.", handler),
      "i" = "See ?vsi_url for supported handlers.",
      "!" = sprintf("Did you mean one of: vsis3, vsigs, vsiaz, vsizip, vsitar, vsicurl, ...?")
    ),
    class = "gdalcli_unsupported_handler"
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
    "- vsi7z: 7z archives (GDAL ≥ 3.7.0)",
    "- vsirar: RAR archives (GDAL ≥ 3.7.0)",
    "- vsisubfile: Byte range within a file",
    "- vsicrypt: Encrypted files",
    "- vsicached: Cached file wrapper",
    "- vsisparse: Sparse file wrapper",
    "",
    "Each handler can use streaming=TRUE for streaming variants (e.g., vsis3_streaming)"
  )
  paste(methods, collapse = "\n")
}
