#' Create Process-Isolated AWS S3 Authentication Environment Variables
#'
#' @description
#' Reads AWS S3 authentication from environment variables for use with [gdal_with_env()].
#' Set credentials via `~/.Renviron`: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
#'
#' @param no_sign_request Logical. If `TRUE`, allows unsigned (public) bucket access.
#'
#' @return Named character vector of environment variables for [gdal_with_env()].
#'
#' @export
gdal_auth_s3 <- function(no_sign_request = FALSE) {
  env_vars <- character()

  if (no_sign_request) {
    env_vars["AWS_NO_SIGN_REQUEST"] <- "YES"
    return(env_vars)
  }

  # Check for required credentials in environment
  access_key <- Sys.getenv("AWS_ACCESS_KEY_ID", unset = NA)
  secret_key <- Sys.getenv("AWS_SECRET_ACCESS_KEY", unset = NA)

  if (is.na(access_key) || is.na(secret_key)) {
    rlang::abort(
      c(
        "AWS S3 credentials not found in environment variables.",
        "i" = "Set the following environment variables:",
        "i" = "  AWS_ACCESS_KEY_ID",
        "i" = "  AWS_SECRET_ACCESS_KEY",
        "",
        "Recommended: Add to your ~/.Renviron file:",
        "  AWS_ACCESS_KEY_ID=your_key_id",
        "  AWS_SECRET_ACCESS_KEY=your_secret_key",
        "",
        "Or use: Sys.setenv(AWS_ACCESS_KEY_ID = '...', AWS_SECRET_ACCESS_KEY = '...')",
        "",
        "For public bucket access (no credentials needed):",
        "  auth <- gdal_auth_s3(no_sign_request = TRUE)"
      ),
      class = "gdalcli_missing_credentials"
    )
  }

  env_vars["AWS_ACCESS_KEY_ID"] <- access_key
  env_vars["AWS_SECRET_ACCESS_KEY"] <- secret_key

  # Optional: Session token for temporary credentials
  session_token <- Sys.getenv("AWS_SESSION_TOKEN", unset = NA)
  if (!is.na(session_token)) {
    env_vars["AWS_SESSION_TOKEN"] <- session_token
  }

  # Optional: Region
  region <- Sys.getenv("AWS_REGION", unset = NA)
  if (!is.na(region)) {
    env_vars["AWS_REGION"] <- region
  }

  env_vars
}


#' Create Process-Isolated Azure Blob Storage Authentication Environment Variables
#'
#' @description
#' Reads Azure Blob Storage authentication from environment variables for use with [gdal_with_env()].
#' Set credentials via `~/.Renviron`: `AZURE_STORAGE_CONNECTION_STRING` or account + key/token.
#'
#' @param no_sign_request Logical. If `TRUE`, allows public container access without credentials.
#'
#' @return Named character vector of environment variables for [gdal_with_env()].
#'
#' @section Setting Up Credentials:
#'
#' **Option 1: Connection String (Recommended)**
#'
#' Add to your `~/.Renviron` or project `.Renviron`:
#' ```
#' AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...
#' ```
#'
#' **Option 2: Account + Access Key**
#'
#' Add to your `~/.Renviron`:
#' ```
#' AZURE_STORAGE_ACCOUNT=myaccount
#' AZURE_STORAGE_ACCESS_KEY=your_access_key
#' ```
#'
#' **Option 3: Account + SAS Token**
#'
#' Add to your `~/.Renviron`:
#' ```
#' AZURE_STORAGE_ACCOUNT=myaccount
#' AZURE_STORAGE_SAS_TOKEN=sv=2020-08-04&ss=bfqt&...
#' ```
#'
#' @section Which Method to Use:
#'
#' - **Connection String**: Easiest, recommended for development
#' - **Account + Access Key**: Standard approach
#' - **Account + SAS Token**: Most secure for production (time-limited tokens)
#'
#' @section Usage Example:
#'
#' ```r
#' # In your .Renviron file:
#' # AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;...
#'
#' # In your R script:
#' auth <- gdal_auth_azure()  # Reads from environment
#'
#' job <- gdal_gdal_vector_convert(
#'   input = gdal_vsi_url("vsiaz", container = "data", path = "file.shp"),
#'   output_format = "GPKG"
#' ) |>
#'   gdal_with_env(auth) |>
#'   gdal_run()
#' ```
#'
#' @section Why No Function Arguments?:
#'
#' Credentials are **intentionally not accepted as function arguments** because:
#' - OK Prevents accidental hardcoding of secrets in R scripts
#' - OK Reduces risk of leaking credentials via version control or logs
#' - OK Encourages secure credential management via .Renviron
#' - OK Follows security best practices (12-factor app)
#'
#' @export
gdal_auth_azure <- function(no_sign_request = FALSE) {
  env_vars <- character()

  if (no_sign_request) {
    env_vars["AZURE_NO_SIGN_REQUEST"] <- "YES"
    return(env_vars)
  }

  # Check for credentials in order of preference
  connection_string <- Sys.getenv("AZURE_STORAGE_CONNECTION_STRING", unset = NA)

  if (!is.na(connection_string)) {
    env_vars["AZURE_STORAGE_CONNECTION_STRING"] <- connection_string
    return(env_vars)
  }

  # Try account + access key
  account <- Sys.getenv("AZURE_STORAGE_ACCOUNT", unset = NA)
  access_key <- Sys.getenv("AZURE_STORAGE_ACCESS_KEY", unset = NA)

  if (!is.na(account) && !is.na(access_key)) {
    env_vars["AZURE_STORAGE_ACCOUNT"] <- account
    env_vars["AZURE_STORAGE_ACCESS_KEY"] <- access_key
    return(env_vars)
  }

  # Try account + SAS token
  sas_token <- Sys.getenv("AZURE_STORAGE_SAS_TOKEN", unset = NA)

  if (!is.na(account) && !is.na(sas_token)) {
    env_vars["AZURE_STORAGE_ACCOUNT"] <- account
    env_vars["AZURE_STORAGE_SAS_TOKEN"] <- sas_token
    return(env_vars)
  }

  # If we get here, no credentials found
  rlang::abort(
    c(
      "Azure Storage credentials not found in environment variables.",
      "i" = "Set ONE of the following combinations:",
      "",
      "Option 1 - Connection String (recommended):",
      "  AZURE_STORAGE_CONNECTION_STRING=...",
      "",
      "Option 2 - Account + Access Key:",
      "  AZURE_STORAGE_ACCOUNT=myaccount",
      "  AZURE_STORAGE_ACCESS_KEY=your_key",
      "",
      "Option 3 - Account + SAS Token:",
      "  AZURE_STORAGE_ACCOUNT=myaccount",
      "  AZURE_STORAGE_SAS_TOKEN=sv=2020-08-04&...",
      "",
      "Add these to your ~/.Renviron file.",
      "",
      "For public container access (no credentials needed):",
      "  auth <- gdal_auth_azure(no_sign_request = TRUE)"
    ),
    class = "gdalcli_missing_credentials"
  )
}


#' Create Process-Isolated Google Cloud Storage Authentication Environment Variables
#'
#' @description
#' Reads Google Cloud Storage authentication from environment variables for use with [gdal_with_env()].
#' Set `GOOGLE_APPLICATION_CREDENTIALS` environment variable pointing to JSON credentials file.
#'
#' @param no_sign_request Logical. If `TRUE`, allows public bucket access without credentials.
#'
#' @return Named character vector of environment variables for [gdal_with_env()].
#'
#' @details
#' Design choices:
#' - Prevents accidental hardcoding of secrets in R scripts
#' - Reduces risk of leaking credentials via version control or logs
#' - Encourages secure credential management via .Renviron
#' - Follows security best practices (12-factor app)
#'
#' @export
gdal_auth_gcs <- function(no_sign_request = FALSE) {
  env_vars <- character()

  if (no_sign_request) {
    env_vars["GS_NO_SIGN_REQUEST"] <- "YES"
    return(env_vars)
  }

  # Check for credentials file path in environment
  credentials_file <- Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS", unset = NA)

  if (is.na(credentials_file)) {
    rlang::abort(
      c(
        "Google Cloud Storage credentials not found in environment variables.",
        "i" = "Set the GOOGLE_APPLICATION_CREDENTIALS variable:",
        "i" = "  GOOGLE_APPLICATION_CREDENTIALS=path/to/credentials.json",
        "",
        "Add to your ~/.Renviron file:",
        "  GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json",
        "",
        "Or use the gcloud CLI:",
        "  gcloud auth application-default login",
        "",
        "For public bucket access (no credentials needed):",
        "  auth <- gdal_auth_gcs(no_sign_request = TRUE)"
      ),
      class = "gdalcli_missing_credentials"
    )
  }

  # Expand ~ to home directory if present
  credentials_file <- path.expand(credentials_file)

  # Verify the credentials file exists
  if (!file.exists(credentials_file)) {
    rlang::abort(
      c(
        sprintf("Google Cloud credentials file not found: %s", credentials_file),
        "i" = "Check that GOOGLE_APPLICATION_CREDENTIALS points to a valid file.",
        "i" = "Current value: ", Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS")
      ),
      class = "gdalcli_invalid_credentials_path"
    )
  }

  env_vars["GOOGLE_APPLICATION_CREDENTIALS"] <- credentials_file
  env_vars
}


#' Create Process-Isolated Alibaba Cloud OSS Authentication Environment Variables
#'
#' @description
#' Reads Alibaba Cloud OSS authentication from environment variables for use with [gdal_with_env()].
#' Set `OSS_ENDPOINT`, `OSS_ACCESS_KEY_ID`, and `OSS_SECRET_ACCESS_KEY` in `~/.Renviron`.
#'
#' @param no_sign_request Logical. If `TRUE`, allows public bucket access without credentials.
#'
#' @return Named character vector of environment variables for [gdal_with_env()].
#'
#' @details
#' Credentials are **intentionally not accepted as function arguments** because:
#' - Prevents accidental hardcoding of secrets in R scripts
#' - Reduces risk of leaking credentials via version control or logs
#' - Encourages secure credential management via .Renviron
#' - Follows security best practices (12-factor app)
#'
#' @export
gdal_auth_oss <- function(no_sign_request = FALSE) {
  env_vars <- character()

  if (no_sign_request) {
    env_vars["OSS_NO_SIGN_REQUEST"] <- "YES"
    return(env_vars)
  }

  # Check for required credentials in environment
  endpoint <- Sys.getenv("OSS_ENDPOINT", unset = NA)
  access_key <- Sys.getenv("OSS_ACCESS_KEY_ID", unset = NA)
  secret_key <- Sys.getenv("OSS_SECRET_ACCESS_KEY", unset = NA)

  if (is.na(endpoint) || is.na(access_key) || is.na(secret_key)) {
    rlang::abort(
      c(
        "Alibaba Cloud OSS credentials not found in environment variables.",
        "i" = "Set the following environment variables:",
        "i" = "  OSS_ENDPOINT (e.g., http://oss-cn-hangzhou.aliyuncs.com)",
        "i" = "  OSS_ACCESS_KEY_ID",
        "i" = "  OSS_SECRET_ACCESS_KEY",
        "",
        "Add to your ~/.Renviron file.",
        "",
        "For public bucket access (no credentials needed):",
        "  auth <- gdal_auth_oss(no_sign_request = TRUE)"
      ),
      class = "gdalcli_missing_credentials"
    )
  }

  env_vars["OSS_ENDPOINT"] <- endpoint
  env_vars["OSS_ACCESS_KEY_ID"] <- access_key
  env_vars["OSS_SECRET_ACCESS_KEY"] <- secret_key

  # Optional: Session token for temporary credentials
  session_token <- Sys.getenv("OSS_SESSION_TOKEN", unset = NA)
  if (!is.na(session_token)) {
    env_vars["OSS_SESSION_TOKEN"] <- session_token
  }

  env_vars
}


#' Create Process-Isolated OpenStack Swift Authentication Environment Variables
#'
#' @description
#' Reads OpenStack Swift authentication from environment variables for use with [gdal_with_env()].
#' Supports Auth V1 and Keystone V3. Set appropriate variables in `~/.Renviron`.
#'
#' @param auth_version Character string. Either `"1"` for Auth V1 or `"3"` for Keystone V3.
#'
#' @return Named character vector of environment variables for [gdal_with_env()].
#'
#' @export
gdal_auth_swift <- function(auth_version = "3") {
  env_vars <- character()

  if (auth_version == "1") {
    # Auth V1
    auth_url <- Sys.getenv("SWIFT_AUTH_V1_URL", unset = NA)
    user <- Sys.getenv("SWIFT_USER", unset = NA)
    key <- Sys.getenv("SWIFT_KEY", unset = NA)

    if (is.na(auth_url) || is.na(user) || is.na(key)) {
      rlang::abort(
        c(
          "OpenStack Swift Auth V1 credentials not found in environment variables.",
          "i" = "Set the following environment variables:",
          "i" = "  SWIFT_AUTH_V1_URL",
          "i" = "  SWIFT_USER",
          "i" = "  SWIFT_KEY",
          "",
          "Add to your ~/.Renviron file."
        ),
        class = "gdalcli_missing_credentials"
      )
    }

    env_vars["SWIFT_AUTH_V1_URL"] <- auth_url
    env_vars["SWIFT_USER"] <- user
    env_vars["SWIFT_KEY"] <- key
  } else if (auth_version == "3") {
    # Keystone V3
    auth_url <- Sys.getenv("OS_AUTH_URL", unset = NA)
    user <- Sys.getenv("OS_USERNAME", unset = NA)
    key <- Sys.getenv("OS_PASSWORD", unset = NA)

    if (is.na(auth_url) || is.na(user) || is.na(key)) {
      rlang::abort(
        c(
          "OpenStack Swift Keystone V3 credentials not found in environment variables.",
          "i" = "Set the following environment variables:",
          "i" = "  OS_AUTH_URL",
          "i" = "  OS_USERNAME",
          "i" = "  OS_PASSWORD",
          "i" = "  OS_PROJECT_NAME (optional)",
          "i" = "  OS_PROJECT_DOMAIN_NAME (optional, default: 'default')",
          "",
          "Add to your ~/.Renviron file."
        ),
        class = "gdalcli_missing_credentials"
      )
    }

    env_vars["OS_IDENTITY_API_VERSION"] <- "3"
    env_vars["OS_AUTH_URL"] <- auth_url
    env_vars["OS_USERNAME"] <- user
    env_vars["OS_PASSWORD"] <- key

    # Optional fields
    project_domain <- Sys.getenv("OS_PROJECT_DOMAIN_NAME", unset = NA)
    if (!is.na(project_domain)) {
      env_vars["OS_PROJECT_DOMAIN_NAME"] <- project_domain
    } else {
      env_vars["OS_PROJECT_DOMAIN_NAME"] <- "default"
    }

    project_name <- Sys.getenv("OS_PROJECT_NAME", unset = NA)
    if (!is.na(project_name)) {
      env_vars["OS_PROJECT_NAME"] <- project_name
    }
  } else {
    rlang::abort(
      c(
        "auth_version must be '1' (Auth V1) or '3' (Keystone V3).",
        "x" = sprintf("Got: %s", auth_version)
      )
    )
  }

  env_vars
}


#' @keywords internal
#' @noRd
sanitize_sas_token <- function(sas_token) {
  # Remove leading ?
  if (substr(sas_token, 1, 1) == "?") {
    sas_token <- substr(sas_token, 2, nchar(sas_token))
  }

  # Remove trailing &
  if (substr(sas_token, nchar(sas_token), nchar(sas_token)) == "&") {
    sas_token <- substr(sas_token, 1, nchar(sas_token) - 1)
  }

  sas_token
}
