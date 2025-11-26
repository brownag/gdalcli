#' Wrapper-Based VSI Handler Functions
#'
#' Internal functions for wrapper/archive VSI handlers that support recursive composition.
#' These handlers can accept the output of other `vsi_url()` calls as their
#' `archive_path` argument, enabling complex nested scenarios like accessing a
#' shapefile within a ZIP on S3.
#'
#' @keywords internal
#' @name wrapper_handlers

#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsizip_url: ZIP, KMZ, ODS, XLSX Archives
#'
#' **GDAL Version:** \eqn{\ge} Pre-3.0 (mature in all 3.x versions)
#'
#' **Syntax:**
#' - Standard (local/regular paths): `/vsizip/path/to/archive.zip/file/in/archive.shp`
#' - Explicit chaining (VSI paths): `/vsizip/{/vsis3/bucket/archive.zip}//file/in/archive.shp`
#'
#' **Recognized Extensions:** .zip, .kmz, .ods, .xlsx
#'
#' **Chaining:** Can accept output of other `vsi_url()` calls as `archive_path`.
#' If a VSI path is detected, automatic explicit chaining syntax with `{...}` and `//`
#' is applied.
#'
#' **Parameters:**
#' - `archive_path`: Path to the ZIP archive (local file, VSI path, or HTTP(S) URL)
#' - `file_in_archive`: Character string or NULL. Path to the file within the archive.
#'   If NULL, returns the archive path itself (useful for inspection).
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, warns about non-recognized archive extensions.
#'   Default FALSE (allows flexibility for extensionless URLs).
#'
#' @examples
#' # Simple local ZIP
#' vsi_url("vsizip", archive_path = "data.zip", file_in_archive = "layer.shp")
#'
#' # ZIP on HTTP(S)
#' zip_url <- vsi_url("vsicurl", url = "https://example.com/data.zip")
#' vsi_url("vsizip", archive_path = zip_url, file_in_archive = "layer.shp")
#'
#' # ZIP on S3 (recursive composition)
#' s3_zip <- vsi_url("vsis3", bucket = "my-bucket", key = "archive.zip")
#' vsi_url("vsizip", archive_path = s3_zip, file_in_archive = "layer.shp")
#'
#' # Direct function call
#' vsizip_url(archive_path = "data.zip", file_in_archive = "layer.shp")
vsizip_url <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- .validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- .validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  .compose_wrapper_vsi_path("vsizip", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsitar_url: TAR, TGZ, TAR.GZ Archives
#'
#' **GDAL Version:** \eqn{\ge} Pre-3.0 (mature in all 3.x versions)
#'
#' **Syntax:**
#' - Standard (local/regular paths): `/vsitar/path/to/archive.tar.gz/file/in/archive.shp`
#' - Explicit chaining (VSI paths): `/vsitar/{/vsis3/bucket/archive.tar.gz}//file/in/archive.shp`
#'
#' **Recognized Extensions:** .tar, .tgz, .tar.gz, .tar.bz2, .tar.xz, .tar.zst
#'
#' **Chaining:** Can accept output of other `vsi_url()` calls as `archive_path`.
#' If a VSI path is detected, automatic explicit chaining syntax with `{...}` and `//`
#' is applied.
#'
#' **Parameters:**
#' - `archive_path`: Path to the TAR archive (local file, VSI path, or HTTP(S) URL)
#' - `file_in_archive`: Character string or NULL. Path to the file within the archive.
#'   If NULL, returns the archive path itself.
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, validates archive extension. Default FALSE.
#'
#' @examples
#' # Simple local TAR.GZ
#' vsi_url("vsitar", archive_path = "data.tar.gz", file_in_archive = "layer.shp")
#'
#' # TAR.GZ on HTTP(S)
#' tar_url <- vsi_url("vsicurl", url = "https://example.com/data.tar.gz")
#' vsi_url("vsitar", archive_path = tar_url, file_in_archive = "layer.shp")
#'
#' # Direct function call
#' vsitar_url(archive_path = "data.tar.gz", file_in_archive = "layer.shp")
vsitar_url <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- .validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- .validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  .compose_wrapper_vsi_path("vsitar", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsi7z_url: 7z Archives
#'
#' **GDAL Version:** \eqn{\ge} 3.7.0 (with libarchive support)
#'
#' **Syntax:**
#' - Standard (local/regular paths): `/vsi7z/path/to/archive.7z/file/in/archive.shp`
#' - Explicit chaining (VSI paths): `/vsi7z/{/vsis3/bucket/archive.7z}//file/in/archive.shp`
#'
#' **Recognized Extensions:** .7z, .lpk, .lpkx, .mpk
#'
#' **Requirements:** libarchive support compiled into GDAL.
#'
#' **Chaining:** Can accept output of other `vsi_url()` calls as `archive_path`.
#' If a VSI path is detected, automatic explicit chaining syntax is applied.
#'
#' **Parameters:**
#' - `archive_path`: Path to the 7z archive (local file, VSI path, or HTTP(S) URL)
#' - `file_in_archive`: Character string or NULL. Path to the file within the archive.
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, validates archive extension. Default FALSE.
#'
#' @examples
#' # Simple local 7z archive
#' vsi_url("vsi7z", archive_path = "data.7z", file_in_archive = "layer.shp")
#'
#' # Direct function call
#' vsi7z_url(archive_path = "data.7z", file_in_archive = "layer.shp")
vsi7z_url <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- .validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- .validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  .compose_wrapper_vsi_path("vsi7z", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsirar_url: RAR Archives
#'
#' **GDAL Version:** \eqn{\ge} 3.7.0 (with libarchive support)
#'
#' **Syntax:**
#' - Standard (local/regular paths): `/vsirar/path/to/archive.rar/file/in/archive.shp`
#' - Explicit chaining (VSI paths): `/vsirar/{/vsis3/bucket/archive.rar}//file/in/archive.shp`
#'
#' **Recognized Extensions:** .rar
#'
#' **Requirements:** libarchive support compiled into GDAL.
#'
#' **Chaining:** Can accept output of other `vsi_url()` calls as `archive_path`.
#' If a VSI path is detected, automatic explicit chaining syntax is applied.
#'
#' **Parameters:**
#' - `archive_path`: Path to the RAR archive (local file, VSI path, or HTTP(S) URL)
#' - `file_in_archive`: Character string or NULL. Path to the file within the archive.
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, validates archive extension. Default FALSE.
#'
#' @examples
#' # Simple local RAR archive
#' vsi_url("vsirar", archive_path = "data.rar", file_in_archive = "layer.shp")
#'
#' # Direct function call
#' vsirar_url(archive_path = "data.rar", file_in_archive = "layer.shp")
vsirar_url <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- .validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- .validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  .compose_wrapper_vsi_path("vsirar", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsisubfile_url: Byte Range / Subfile Access
#'
#' **GDAL Version:** \eqn{\ge} 2.1.0
#'
#' **Syntax:**
#' - Format: `/vsisubfile/offset,size/{path}` or `/vsisubfile/offset/{path}`
#' - With VSI paths: `/vsisubfile/0,1000/{/vsis3/bucket/data.bin}`
#'
#' **Use Cases:** Access specific byte ranges of files; extract embedded rasters
#' or binary data without copying entire file.
#'
#' **Parameters:**
#' - `offset`: Integer. Starting byte position (0-indexed).
#' - `size`: Integer or NULL. Number of bytes to read. If NULL, reads to end of file.
#' - `filename`: Character string. File path (local, VSI, or HTTP(S) URL).
#'
#' **Validation:** `offset` and `size` (if specified) must be non-negative integers.
#' Size of 0 or negative with non-zero offset is invalid.
#'
#' @examples
#' # Read first 1000 bytes
#' vsi_url("vsisubfile", offset = 0L, size = 1000L, filename = "large.bin")
#'
#' # Read from byte 5000 to end
#' vsi_url("vsisubfile", offset = 5000L, size = NULL, filename = "data.bin")
#'
#' # Read from S3 file
#' vsi_url("vsisubfile", offset = 0L, size = 100L,
#'         filename = vsi_url("vsis3", bucket = "data", key = "file.bin"))
#'
#' # Direct function call
#' vsisubfile_url(offset = 0L, size = 1000L, filename = "large.bin")
vsisubfile_url <- function(offset = 0L, size = NULL, filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    if (!is.numeric(offset) || offset < 0) {
      rlang::abort("Parameter 'offset' must be a non-negative number.")
    }
    if (!is.numeric(size) || size <= 0) {
      rlang::abort("Parameter 'size' must be a positive number.")
    }
    filename <- .validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  # Convert offset and size to integers for composition
  offset_int <- as.integer(offset)
  size_int <- as.integer(size)

  prefix <- .compose_vsi_prefix("vsisubfile", streaming)

  is_vsi <- .is_vsi_path(filename)

  if (is_vsi) {
    # Explicit chaining: /vsisubfile/OFFSET_SIZE,{vsi_path}
    paste0(prefix, offset_int, "_", size_int, ",{", filename, "}")
  } else {
    # Standard: /vsisubfile/OFFSET_SIZE,path
    paste0(prefix, offset_int, "_", size_int, ",", filename)
  }
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsicrypt_url: On-the-Fly Encryption/Decryption
#'
#' **GDAL Version:** \eqn{\ge} 2.2.0
#'
#' **Syntax:**
#' - Format: `/vsicrypt/key={key_spec}/alg={algorithm}/{path}`
#' - Example: `/vsicrypt/key=mypassword/alg=AES_256_GCM//vsis3/bucket/encrypted.bin`
#'
#' **Requirements:** GDAL built with OpenSSL or similar cryptography support.
#' Algorithm support depends on compile-time options.
#'
#' **Encryption/Decryption:** Automatically encrypts on write, decrypts on read.
#' The key and algorithm must be specified before the file path.
#'
#' **Parameters:**
#' - `filename`: Character string. File path (local, VSI, or HTTP(S) URL).
#' - `key`: Character string. The encryption key (plaintext or base64-encoded).
#' - `key_format`: Character string. One of "plaintext" or "base64". Default "plaintext".
#' - `alg`: Character string. Algorithm (e.g., "AES_256_GCM", "AES_256_CBC").
#'   Default "AES_256_GCM" (recommended).
#'
#' @examples
#' # Decrypt with plaintext key
#' vsi_url("vsicrypt", key = "mypassword", alg = "AES_256_GCM",
#'         filename = "encrypted.bin")
#'
#' # Decrypt with base64-encoded key
#' vsi_url("vsicrypt", key = "bXlwYXNzd29yZA==", key_format = "base64",
#'         filename = "encrypted.bin")
#'
#' # Direct function call
#' vsicrypt_url(key = "mypassword", alg = "AES_256_GCM", filename = "encrypted.bin")
vsicrypt_url <- function(key, filename, key_format = "plaintext", ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    key <- .validate_path_component(key, "key", allow_empty = FALSE)
    filename <- .validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  key_format <- match.arg(key_format, c("plaintext", "base64"))

  prefix <- .compose_vsi_prefix("vsicrypt", streaming)

  is_vsi <- .is_vsi_path(filename)

  # Determine key parameter syntax
  key_param <- if (key_format == "base64") "key_b64" else "key"

  if (is_vsi) {
    # Explicit chaining: /vsicrypt/key=...,file={vsi_path}
    paste0(prefix, key_param, "=", key, ",file={", filename, "}")
  } else {
    # Standard: /vsicrypt/key=...,file=path
    paste0(prefix, key_param, "=", key, ",file=", filename)
  }
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsicached_url: File Caching Layer
#'
#' **GDAL Version:** \eqn{\ge} 3.8.0
#'
#' **Syntax:**
#' - Format: `/vsicached/{path}`
#' - Example: `/vsicached/{/vsis3/bucket/data.tif}`
#'
#' **Use Cases:** Cache frequently accessed remote files to disk for improved
#' performance. Useful for reading same remote files multiple times or streaming
#' scenarios with heavy I/O.
#'
#' **Cache Location:** Stored in temporary directory (configurable via
#' `GDAL_DISABLE_READDIR_ON_OPEN` and related options).
#'
#' **Parameters:**
#' - `filename`: Character string. File path (VSI path, HTTP(S) URL, etc.).
#'   Note: Most useful with remote sources (not local files).
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#'
#' @examples
#' # Cache remote GeoTIFF from S3
#' vsi_url("vsicached", filename = vsi_url("vsis3", bucket = "data", key = "dem.tif"))
#'
#' # Cache from HTTP(S)
#' http_url <- vsi_url("vsicurl", url = "https://example.com/data.tif")
#' vsi_url("vsicached", filename = http_url)
#'
#' # Direct function call
#' vsicached_url(filename = vsi_url("vsis3", bucket = "data", key = "dem.tif"))
vsicached_url <- function(filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    filename <- .validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  prefix <- .compose_vsi_prefix("vsicached", streaming)

  is_vsi <- .is_vsi_path(filename)

  if (is_vsi) {
    paste0(prefix, "{", filename, "}")
  } else {
    paste0(prefix, filename)
  }
}


#' @export
#' @rdname wrapper_handlers
#'
#' @details
#' ## vsisparse_url: Sparse File Handler
#'
#' **GDAL Version:** \eqn{\ge} 3.1.0
#'
#' **Syntax:**
#' - Format: `/vsisparse/{path}`
#' - Example: `/vsisparse/{/vsis3/bucket/sparse_data.bin}`
#'
#' **Use Cases:** Efficiently handle files with "holes" or unallocated regions.
#' Useful for large binary files where most of the space is uninitialized or sparse.
#'
#' **Behavior:** Detects and handles sparse regions within files, potentially
#' reducing memory footprint and I/O operations for files with significant
#' unallocated regions.
#'
#' **Parameters:**
#' - `filename`: Character string. File path (local, VSI path, or HTTP(S) URL).
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#'
#' @examples
#' # Access sparse file from local filesystem
#' vsi_url("vsisparse", filename = "sparse_data.bin")
#'
#' # Access sparse file from S3
#' vsi_url("vsisparse", filename = vsi_url("vsis3", bucket = "data", key = "sparse.bin"))
#'
#' # Direct function call
#' vsisparse_url(filename = "sparse_data.bin")
vsisparse_url <- function(filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    filename <- .validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  prefix <- .compose_vsi_prefix("vsisparse", streaming)

  is_vsi <- .is_vsi_path(filename)

  if (is_vsi) {
    paste0(prefix, "{", filename, "}")
  } else {
    paste0(prefix, filename)
  }
}
