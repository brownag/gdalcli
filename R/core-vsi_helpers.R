#' Internal Helper Functions for VSI URL Composition
#'
#' These functions are used internally by `vsi_url` methods for validation,
#' path detection, and sanitization.
#'
#' @details
#' - `.is_vsi_path()`: Check if a path is a VSI path (starts with /vsi)
#' - `.validate_path_component()`: Validate a single path component
#' - `.sanitize_sas_token()`: Remove leading `?` and trailing `&` from SAS tokens
#'
#' @keywords internal
#' @name vsi_helpers
#' @noRd
.is_vsi_path <- function(path) {
  if (!is.character(path) || length(path) == 0) {
    return(FALSE)
  }
  grepl("^/vsi[a-z0-9_]+/", path, ignore.case = TRUE)
}


.validate_path_component <- function(component, name, allow_empty = FALSE, allow_na = TRUE) {
  if (is.na(component)) {
    if (allow_na) {
      return(component)
    } else {
      rlang::abort(sprintf("Parameter '%s' cannot be NA.", name))
    }
  }

  if (is.null(component)) {
    rlang::abort(sprintf("Parameter '%s' cannot be NULL.", name))
  }

  if (!is.character(component)) {
    rlang::abort(
      sprintf("Parameter '%s' must be a character string, not %s.", name, class(component)[1])
    )
  }

  if (length(component) != 1) {
    rlang::abort(sprintf("Parameter '%s' must be a single string, not length %d.", name, length(component)))
  }

  if (nchar(component) == 0 && !allow_empty) {
    rlang::abort(sprintf("Parameter '%s' cannot be an empty string.", name))
  }

  component
}


.sanitize_sas_token <- function(token) {
  if (!is.character(token) || length(token) != 1) {
    rlang::abort("SAS token must be a single character string.")
  }

  original <- token
  removed_chars <- c()

  # Strip leading '?' or '&'
  if (grepl("^[?&]", token)) {
    removed_chars <- c(removed_chars, sub("^([?&]).*", "\\1", token))
    token <- sub("^[?&]", "", token)
  }

  # Strip trailing '&'
  if (grepl("&$", token)) {
    removed_chars <- c(removed_chars, "&")
    token <- sub("&$", "", token)
  }

  if (length(removed_chars) > 0) {
    msg <- sprintf(
      "Sanitized Azure SAS token: removed leading '%s' and trailing '&'.",
      paste(unique(removed_chars), collapse = "', '")
    )
    cli::cli_alert_info(msg)
  }

  token
}


#' Check if a path is a GDAL Virtual File System (VSI) path
#'
#' @param path Character string to check
#'
#' @return Logical indicating if the path starts with a VSI prefix (e.g., `/vsis3/`, `/vsizip/`)
#'
#' @examples
#' is_vsi_path("/vsis3/bucket/key")  # TRUE
#' is_vsi_path("/home/user/file.tif")  # FALSE
#'
#' @export
is_vsi_path <- function(path) {
  .is_vsi_path(path)
}


#' Validate a path component for VSI URL composition
#'
#' @param component Character string to validate
#' @param name Character string name of the parameter (for error messages)
#' @param allow_empty Logical. If TRUE, empty strings are allowed
#' @param allow_na Logical. If TRUE, NA values are allowed
#'
#' @return The validated component (unchanged if valid)
#'
#' @examples
#' validate_path_component("valid", "bucket")  # "valid"
#' \dontrun{
#' validate_path_component(NULL, "bucket")  # Error
#' }
#'
#' @export
validate_path_component <- function(component, name, allow_empty = FALSE, allow_na = TRUE) {
  .validate_path_component(component, name, allow_empty, allow_na)
}


#' Sanitize an Azure SAS token by removing leading/trailing delimiters
#'
#' @param token Character string SAS token
#'
#' @return Character string with leading `?`/`&` and trailing `&` removed
#'
#' @examples
#' sanitize_sas_token("?st=2023&sig=...")  # "st=2023&sig=..."
#' sanitize_sas_token("st=2023&sig=...&")  # "st=2023&sig=..."
#'
#' @export
sanitize_sas_token <- function(token) {
  .sanitize_sas_token(token)
}


#' Compose a wrapper VSI path with automatic chaining detection
#'
#' @param handler Character string for handler name (e.g., "vsizip")
#' @param archive_path Character string for the archive/inner path
#' @param file_in_archive Character string or NULL for the file within archive
#' @param streaming Logical. If TRUE, use streaming variant
#'
#' @return Character string composed according to VSI chaining syntax
#'
#' @examples
#' \dontrun{
#' compose_wrapper_vsi_path("vsizip", "archive.zip", "file.txt")
#' compose_wrapper_vsi_path("vsizip", "/vsis3/bucket/archive.zip", "file.txt")
#' }
#'
#' @export
compose_wrapper_vsi_path <- function(handler, archive_path, file_in_archive = NULL, streaming = FALSE) {
  .compose_wrapper_vsi_path(handler, archive_path, file_in_archive, streaming)
}


#' Compose a VSI URL prefix with optional streaming suffix
#'
#' @param handler Character string for the handler name (without '/' prefix)
#' @param streaming Logical. If TRUE, append '_streaming' to handler name
#'
#' @return Character string like "/vsis3" or "/vsis3_streaming" with leading slash
#'
#' @keywords internal
#' @noRd
.compose_vsi_prefix <- function(handler, streaming = FALSE) {
  prefix <- tolower(handler)
  if (streaming) {
    prefix <- paste0(prefix, "_streaming")
  }
  paste0("/", prefix, "/")
}


#' Compose a wrapper VSI path with automatic chaining detection
#'
#' @param handler Character string for handler name
#' @param archive_path Character string for the archive/inner path
#' @param file_in_archive Character string or NULL for the file within archive
#' @param streaming Logical. If TRUE, use streaming variant
#'
#' @return Character string composed according to VSI chaining syntax
#'
#' @details
#' Implements the core VSI chaining logic:
#' - If archive_path is a VSI path (starts with /vsi), uses explicit chaining syntax
#' - Otherwise uses standard syntax: `/handler/archive_path/file_in_archive`
#'
#' @keywords internal
#' @noRd
.compose_wrapper_vsi_path <- function(handler, archive_path, file_in_archive = NULL, streaming = FALSE) {
  prefix <- .compose_vsi_prefix(handler, streaming)

  is_vsi <- .is_vsi_path(archive_path)

  if (is_vsi) {
    # Explicit chaining syntax with curly braces
    if (!is.null(file_in_archive)) {
      return(paste0(prefix, "{", archive_path, "}//", file_in_archive))
    } else {
      return(paste0(prefix, "{", archive_path, "}"))
    }
  } else {
    # Standard syntax for local/regular paths
    if (!is.null(file_in_archive)) {
      return(paste0(prefix, archive_path, "/", file_in_archive))
    } else {
      return(paste0(prefix, archive_path))
    }
  }
}
