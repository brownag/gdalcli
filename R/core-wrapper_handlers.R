#' Wrapper-Based VSI Handler Methods
#'
#' S3 methods for wrapper/archive VSI handlers that support recursive composition.
#' These handlers can accept the output of other `vsi_url()` calls as their
#' `archive_path` argument, enabling complex nested scenarios like accessing a
#' shapefile within a ZIP on S3.
#'
#' @keywords internal
#' @name wrapper_handlers


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsizip: ZIP, KMZ, ODS, XLSX Archives
#'
#' **GDAL Version:** ≥ Pre-3.0 (mature in all 3.x versions)
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
vsi_url.vsizip <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  compose_wrapper_vsi_path("vsizip", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsitar: TAR, TGZ, TAR.GZ Archives
#'
#' **GDAL Version:** ≥ Pre-3.0 (mature in all 3.x versions)
#'
#' **Syntax:**
#' - Standard: `/vsitar/path/to/archive.tar/file/in/archive.tif`
#' - Explicit chaining: `/vsitar/{/vsis3/bucket/archive.tgz}//file.tif`
#'
#' **Recognized Extensions:** .tar, .tgz, .tar.gz
#'
#' **Chaining:** Supports recursive composition like `vsizip`.
#'
#' **Parameters:**
#' - `archive_path`: Path to the TAR archive (local, VSI, or HTTP(S))
#' - `file_in_archive`: Character string or NULL. Path within the archive.
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, warns about non-TAR extensions. Default FALSE.
#'
#' @examples
#' # TAR.GZ on S3
#' tar_on_s3 <- vsi_url("vsis3", bucket = "bucket", key = "archive.tar.gz")
#' vsi_url("vsitar", archive_path = tar_on_s3, file_in_archive = "layer.tif")
vsi_url.vsitar <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  compose_wrapper_vsi_path("vsitar", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsi7z: 7z Archives
#'
#' **GDAL Version:** ≥ 3.7.0 (requires libarchive; also supports .lpk, .lpkx, .mpk, .mpkx, .ppkx)
#'
#' **Syntax:**
#' - Standard: `/vsi7z/path/to/archive.7z/file/in/archive.tif`
#' - Explicit chaining: `/vsi7z/{/vsis3/bucket/archive.7z}//file.tif`
#'
#' **Recognized Extensions:** .7z, .lpk, .lpkx, .mpk, .mpkx, .ppkx
#'
#' **Chaining:** Supports recursive composition.
#'
#' **Parameters:**
#' - `archive_path`: Path to the 7z archive
#' - `file_in_archive`: Path within the archive, or NULL
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, warns about non-7z extensions. Default FALSE.
#'
#' @examples
#' # 7z archive
#' vsi_url("vsi7z", archive_path = "archive.7z", file_in_archive = "data.tif")
vsi_url.vsi7z <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  compose_wrapper_vsi_path("vsi7z", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsirar: RAR Archives
#'
#' **GDAL Version:** ≥ 3.7.0 (requires libarchive)
#'
#' **Syntax:**
#' - Standard: `/vsirar/path/to/archive.rar/file/in/archive.tif`
#' - Explicit chaining: `/vsirar/{/vsis3/bucket/archive.rar}//file.tif`
#'
#' **Recognized Extensions:** .rar
#'
#' **Chaining:** Supports recursive composition.
#'
#' **Parameters:**
#' - `archive_path`: Path to the RAR archive
#' - `file_in_archive`: Path within the archive, or NULL
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, warns about non-RAR extensions. Default FALSE.
#'
#' @examples
#' # RAR archive
#' vsi_url("vsirar", archive_path = "archive.rar", file_in_archive = "data.tif")
vsi_url.vsirar <- function(archive_path, file_in_archive = NULL, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    archive_path <- validate_path_component(archive_path, "archive_path", allow_empty = FALSE)
    if (!is.null(file_in_archive)) {
      file_in_archive <- validate_path_component(file_in_archive, "file_in_archive", allow_empty = FALSE)
    }
  }

  compose_wrapper_vsi_path("vsirar", archive_path, file_in_archive, streaming)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsisubfile: Byte Range Within a File
#'
#' **GDAL Version:** ≥ Pre-3.0
#'
#' **Syntax:**
#' - Standard: `/vsisubfile/OFFSET_SIZE,path/to/file`
#' - With VSI chaining: `/vsisubfile/1024_512000,{/vsis3/bucket/largefile}`
#'
#' **Purpose:** Exposes a specific byte range (OFFSET and SIZE) of a file as a complete
#' virtual file, useful for reading portions of large files.
#'
#' **Parameters:**
#' - `offset`: Integer. Byte offset where the subfile begins.
#' - `size`: Integer. Length of the subfile in bytes.
#' - `filename`: Path to the parent file (local, VSI, or HTTP(S)).
#'   If this is a VSI path, automatic chaining with `{...}` is applied.
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, validates that offset and size are positive.
#'   Default FALSE.
#'
#' @examples
#' # Read bytes 1024-513023 (512KB starting at byte 1024)
#' vsi_url("vsisubfile", offset = 1024, size = 512000, filename = "largefile.dat")
#'
#' # Subfile within an S3 file
#' s3_file <- vsi_url("vsis3", bucket = "bucket", key = "largefile")
#' vsi_url("vsisubfile", offset = 0, size = 10000, filename = s3_file)
vsi_url.vsisubfile <- function(offset, size, filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    if (!is.numeric(offset) || offset < 0) {
      rlang::abort("Parameter 'offset' must be a non-negative number.")
    }
    if (!is.numeric(size) || size <= 0) {
      rlang::abort("Parameter 'size' must be a positive number.")
    }
    filename <- validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  # Convert offset and size to integers for composition
  offset_int <- as.integer(offset)
  size_int <- as.integer(size)

  prefix <- compose_vsi_prefix("vsisubfile", streaming)

  is_vsi <- is_vsi_path(filename)

  if (is_vsi) {
    # Explicit chaining: /vsisubfile/OFFSET_SIZE,{vsi_path}
    paste0(prefix, offset_int, "_", size_int, ",{", filename, "}")
  } else {
    # Standard: /vsisubfile/OFFSET_SIZE,path
    paste0(prefix, offset_int, "_", size_int, ",", filename)
  }
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsicrypt: Encrypted Files
#'
#' **GDAL Version:** ≥ Pre-3.0 (requires Crypto++ library)
#'
#' **Syntax:** `/vsicrypt/key=VALUE,file={path_to_file}`
#'
#' **Purpose:** On-the-fly encryption/decryption of files. The `file` parameter can be
#' another VSI path to enable scenarios like encrypted archives on S3.
#'
#' **Key Format:** Can be plaintext or base64-encoded.
#'
#' **Parameters:**
#' - `key`: Character string. The encryption key (plaintext).
#' - `filename`: Path to the file to encrypt/decrypt (can be a VSI path for chaining).
#' - `key_format`: Character string. "plaintext" (default) or "base64".
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, checks that key and filename are non-empty.
#'   Default FALSE.
#'
#' @examples
#' # Encrypted file
#' vsi_url("vsicrypt", key = "mysecretkey", filename = "encrypted_data.bin")
#'
#' # Encrypted ZIP on S3
#' s3_zip <- vsi_url("vsis3", bucket = "bucket", key = "encrypted.zip")
#' vsi_url("vsicrypt", key = "secret", filename = s3_zip)
vsi_url.vsicrypt <- function(key, filename, key_format = "plaintext", ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    key <- validate_path_component(key, "key", allow_empty = FALSE)
    filename <- validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  key_format <- match.arg(key_format, c("plaintext", "base64"))

  prefix <- compose_vsi_prefix("vsicrypt", streaming)

  is_vsi <- is_vsi_path(filename)

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
#' @rdname vsi_url
#'
#' @details
#' ## vsicached: File Caching Layer
#'
#' **GDAL Version:** ≥ 3.8.0 (earlier versions may use `/vsicache/`)
#'
#' **Syntax:** `/vsicached/{inner_vsi_path}` or `/vsicached/local_path`
#'
#' **Purpose:** Adds an automatic file caching layer around another file/VSI path,
#' useful for remote data access optimization.
#'
#' **Chaining:** Supports recursive composition.
#'
#' **Parameters:**
#' - `filename`: Path to cache (local, VSI path, or HTTP(S) URL)
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, checks filename is non-empty. Default FALSE.
#'
#' @examples
#' # Cache an S3 file
#' s3_file <- vsi_url("vsis3", bucket = "bucket", key = "large_file.tif")
#' vsi_url("vsicached", filename = s3_file)
vsi_url.vsicached <- function(filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    filename <- validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsicached", streaming)

  is_vsi <- is_vsi_path(filename)

  if (is_vsi) {
    paste0(prefix, "{", filename, "}")
  } else {
    paste0(prefix, filename)
  }
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsisparse: Sparse File Handler
#'
#' **GDAL Version:** ≥ Pre-3.0
#'
#' **Syntax:** `/vsisparse/{inner_vsi_path}` or `/vsisparse/local_path`
#'
#' **Purpose:** Creates or reads sparse files (files with unallocated "holes").
#' Supports recursive composition.
#'
#' **Parameters:**
#' - `filename`: Path to the sparse file
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, checks filename is non-empty. Default FALSE.
#'
#' @examples
#' # Sparse file wrapper
#' vsi_url("vsisparse", filename = "sparse_output.vrt")
vsi_url.vsisparse <- function(filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    filename <- validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsisparse", streaming)

  is_vsi <- is_vsi_path(filename)

  if (is_vsi) {
    paste0(prefix, "{", filename, "}")
  } else {
    paste0(prefix, filename)
  }
}
