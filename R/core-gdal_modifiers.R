#' Add Creation Options to a GDAL Job
#'
#' @description
#' `gdal_with_co()` is an S3 generic for adding creation options (typically `-co` or
#' `--creation-option` in the GDAL CLI) to a [gdal_job] object. Creation options
#' control how GDAL creates new datasets.
#'
#' This function is designed to be used with the native R pipe (`|>`).
#'
#' @param x A [gdal_job] object.
#' @param ... One or more creation option strings (e.g., `"COMPRESS=LZW"`, `"BLOCKXSIZE=256"`).
#'   Strings are appended to the `x$arguments$creation-option` list.
#'
#' @return
#' A modified [gdal_job] object with the creation options added.
#'
#' @seealso
#' [gdal_with_lco()], [gdal_with_oo()], [gdal_with_config()], [gdal_with_env()]
#'
#' @examples
#' \dontrun{
#' job <- gdal_vector_convert("in.shp", "out.gpkg") |>
#'   gdal_with_co("COMPRESS=LZW") |>
#'   gdal_with_co("LAYER_STRATEGY=INDENT")
#'
#' gdal_job_run(job)
#' }
#'
#' @export
gdal_with_co <- function(x, ...) {
  UseMethod("gdal_with_co")
}


#' @rdname gdal_with_co
#' @export
gdal_with_co.gdal_job <- function(x, ...) {
  new_options <- c(...)

  if (!is.character(new_options) || length(new_options) == 0) {
    rlang::abort("Creation options must be non-empty character vector(s).")
  }

  # Get existing creation options or start with empty vector
  existing <- x$arguments[["creation-option"]] %||% character()

  # Append new options
  x$arguments[["creation-option"]] <- c(existing, new_options)

  x
}


#' @export
gdal_with_co.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_with_co method for class '%s'.", class(x)[1]),
      "i" = "gdal_with_co() is designed for gdal_job objects."
    )
  )
}


#' Add Layer Creation Options to a GDAL Job
#'
#' @description
#' `gdal_with_lco()` is an S3 generic for adding layer creation options
#' (typically `-lco` or `--layer-creation-option` in the GDAL CLI) to a [gdal_job] object.
#' Layer creation options control properties of individual layers in multi-layer datasets.
#'
#' This function is designed to be used with the native R pipe (`|>`).
#'
#' @param x A [gdal_job] object.
#' @param ... One or more layer creation option strings.
#'
#' @return
#' A modified [gdal_job] object with the layer creation options added.
#'
#' @seealso
#' [gdal_with_co()], [gdal_with_oo()], [gdal_with_config()], [gdal_with_env()]
#'
#' @examples
#' \dontrun{
#' job <- gdal_vector_convert("in.shp", "out.gpkg") |>
#'   gdal_with_lco("SPATIAL_INDEX=YES") |>
#'   gdal_with_lco("GEOMETRY_NAME=shape")
#'
#' gdal_job_run(job)
#' }
#'
#' @export
gdal_with_lco <- function(x, ...) {
  UseMethod("gdal_with_lco")
}


#' @rdname gdal_with_lco
#' @export
gdal_with_lco.gdal_job <- function(x, ...) {
  new_options <- c(...)

  if (!is.character(new_options) || length(new_options) == 0) {
    rlang::abort("Layer creation options must be non-empty character vector(s).")
  }

  existing <- x$arguments[["layer-creation-option"]] %||% character()
  x$arguments[["layer-creation-option"]] <- c(existing, new_options)

  x
}


#' @export
gdal_with_lco.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_with_lco method for class '%s'.", class(x)[1]),
      "i" = "gdal_with_lco() is designed for gdal_job objects."
    )
  )
}


#' Add Open Options to a GDAL Job
#'
#' @description
#' `gdal_with_oo()` is an S3 generic for adding open options (typically `-oo` or
#' `--open-option` in the GDAL CLI) to a [gdal_job] object. Open options control
#' how GDAL opens/reads input datasets.
#'
#' This function is designed to be used with the native R pipe (`|>`).
#'
#' @param x A [gdal_job] object.
#' @param ... One or more open option strings.
#'
#' @return
#' A modified [gdal_job] object with the open options added.
#'
#' @seealso
#' [gdal_with_co()], [gdal_with_lco()], [gdal_with_config()], [gdal_with_env()]
#'
#' @examples
#' \dontrun{
#' job <- gdal_vector_info("file.gpkg") |>
#'   gdal_with_oo("VERIFY_BUFFERS=NO")
#'
#' gdal_job_run(job)
#' }
#'
#' @export
gdal_with_oo <- function(x, ...) {
  UseMethod("gdal_with_oo")
}


#' @rdname gdal_with_oo
#' @export
gdal_with_oo.gdal_job <- function(x, ...) {
  new_options <- c(...)

  if (!is.character(new_options) || length(new_options) == 0) {
    rlang::abort("Open options must be non-empty character vector(s).")
  }

  existing <- x$arguments[["open-option"]] %||% character()
  x$arguments[["open-option"]] <- c(existing, new_options)

  x
}


#' @export
gdal_with_oo.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_with_oo method for class '%s'.", class(x)[1]),
      "i" = "gdal_with_oo() is designed for gdal_job objects."
    )
  )
}


#' Add GDAL Configuration Options to a GDAL Job
#'
#' @description
#' `gdal_with_config()` is an S3 generic for adding GDAL configuration options
#' (typically `--config` in the GDAL CLI) to a [gdal_job] object. Config options
#' modify GDAL's runtime behavior globally.
#'
#' This function is designed to be used with the native R pipe (`|>`).
#'
#' @param x A [gdal_job] object.
#' @param ... One or more config option strings in the format `"KEY=VALUE"`.
#'
#' @return
#' A modified [gdal_job] object with the config options added.
#'
#' @seealso
#' [gdal_with_co()], [gdal_with_lco()], [gdal_with_oo()], [gdal_with_env()]
#'
#' @examples
#' \dontrun{
#' job <- gdal_vector_convert("in.shp", "out.gpkg") |>
#'   gdal_with_config("OGR_SQL_DIALECT=SQLITE") |>
#'   gdal_with_config("GDAL_CACHEMAX=512")
#'
#' gdal_job_run(job)
#' }
#'
#' @export
gdal_with_config <- function(x, ...) {
  UseMethod("gdal_with_config")
}


#' @rdname gdal_with_config
#' @export
gdal_with_config.gdal_job <- function(x, ...) {
  new_configs <- c(...)

  if (!is.character(new_configs) || length(new_configs) == 0) {
    rlang::abort("Config options must be non-empty character vector(s) in 'KEY=VALUE' format.")
  }

  # Parse KEY=VALUE pairs and add to config_options
  for (config_str in new_configs) {
    parts <- strsplit(config_str, "=", fixed = TRUE)[[1]]
    if (length(parts) != 2) {
      rlang::abort(
        c(
          sprintf("Invalid config option format: '%s'.", config_str),
          "i" = "Expected format: 'KEY=VALUE'"
        )
      )
    }

    key <- parts[1]
    value <- parts[2]

    # Add to named vector (allows duplicates with same key, which overwrites)
    x$config_options[key] <- value
  }

  x
}


#' @export
gdal_with_config.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_with_config method for class '%s'.", class(x)[1]),
      "i" = "gdal_with_config() is designed for gdal_job objects."
    )
  )
}


#' Add Environment Variables to a GDAL Job
#'
#' @description
#' `gdal_with_env()` is an S3 generic for adding environment variables to a
#' [gdal_job] object. Environment variables are passed to the subprocess
#' and affect GDAL's behavior.
#'
#' This is the modern, recommended way to set authentication credentials and other
#' environment-specific state. It is process-isolated and reproducible, unlike the
#' legacy [set_gdal_auth()] approach of using `Sys.setenv()`.
#'
#' This function is designed to be used with the native R pipe (`|>`).
#'
#' @param x A [gdal_job] object.
#' @param ... One or more environment variable specifications:
#'   - If passed as a named list/vector, keys are variable names and values are the values.
#'   - If passed as character strings in `"KEY=VALUE"` format, they are parsed.
#'   - Can use results from helper functions like [gdal_auth_s3()], [gdal_auth_azure()], etc.
#'
#' @return
#' A modified [gdal_job] object with the environment variables added.
#'
#' @seealso
#' [gdal_with_co()], [gdal_with_config()], [gdal_auth_s3()], [gdal_auth_azure()]
#'
#' @examples
#' \dontrun{
#' # Using character vector of KEY=VALUE strings
#' job <- gdal_vector_convert("in.shp", "out.gpkg") |>
#'   gdal_with_env("AWS_ACCESS_KEY_ID=...", "AWS_SECRET_ACCESS_KEY=...")
#'
#' # Using named vector
#' job <- gdal_vector_convert("in.shp", "out.gpkg") |>
#'   gdal_with_env(c(
#'     AWS_ACCESS_KEY_ID = "...",
#'     AWS_SECRET_ACCESS_KEY = "..."
#'   ))
#'
#' # Using auth helper function
#' job <- gdal_vector_convert("in.shp", "out.gpkg") |>
#'   gdal_with_env(gdal_auth_s3(...))
#'
#' gdal_job_run(job)
#' }
#'
#' @export
gdal_with_env <- function(x, ...) {
  UseMethod("gdal_with_env")
}


#' @rdname gdal_with_env
#' @export
gdal_with_env.gdal_job <- function(x, ...) {
  new_envs <- list(...)

  # Convert all arguments to a named character vector
  merged_env <- character()

  for (env_spec in new_envs) {
    if (is.character(env_spec)) {
      # Handle character vector (either named or KEY=VALUE strings)
      if (!is.null(names(env_spec))) {
        # Named vector
        merged_env <- c(merged_env, env_spec)
      } else {
        # Parse KEY=VALUE strings
        for (env_str in env_spec) {
          parts <- strsplit(env_str, "=", fixed = TRUE)[[1]]
          if (length(parts) != 2) {
            rlang::abort(
              c(
                sprintf("Invalid environment variable format: '%s'.", env_str),
                "i" = "Expected format: 'KEY=VALUE'"
              )
            )
          }
          merged_env[parts[1]] <- parts[2]
        }
      }
    } else if (is.list(env_spec)) {
      # Named list
      merged_env <- c(merged_env, unlist(env_spec))
    }
  }

  # Add to job's env_vars (override if duplicate keys)
  x$env_vars <- c(x$env_vars, merged_env)

  x
}


#' @export
gdal_with_env.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_with_env method for class '%s'.", class(x)[1]),
      "i" = "gdal_with_env() is designed for gdal_job objects."
    )
  )
}
