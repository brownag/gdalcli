#' Create Process-Isolated AWS S3 Authentication Environment Variables
#'
#' @description
#' `gdal_auth_s3()` reads AWS S3 authentication credentials from environment
#' variables and returns them as a named character vector suitable for use with
#' [gdal_with_env()].
#'
#' **IMPORTANT**: Credentials are read from environment variables (not from function
#' arguments) to prevent accidental exposure in code repositories. This encourages
#' secure credential management via `.Renviron` files or external secret managers.
#'
#' This is the modern, recommended approach: it avoids global state pollution,
#' ensures credentials are process-isolated, and works correctly in parallel
#' execution contexts.
#'
#' @param no_sign_request Logical. If `TRUE`, configures unsigned (public) bucket
#'   access without requiring credentials. Default `FALSE`.
#'
#' @return
#' A named character vector of environment variables suitable for passing to
#' [gdal_with_env()]. Keys are variable names like `AWS_ACCESS_KEY_ID`; values
#' are the corresponding credentials read from the environment.
#'
#' @section Setting Up Credentials:
#'
#' **Option 1: Using .Renviron (Recommended)**
#'
#' Add to your `~/.Renviron` or project `.Renviron`:
#' ```
#' AWS_ACCESS_KEY_ID=your_access_key_id
#' AWS_SECRET_ACCESS_KEY=your_secret_access_key
#' AWS_SESSION_TOKEN=optional_session_token
#' AWS_REGION=us-west-2
#' ```
#'
#' Then restart R or run `readRenviron("~/.Renviron")`.
#'
#' **Option 2: Using Sys.setenv() (Temporary, for this session only)**
#'
#' ```r
#' Sys.setenv(
#'   AWS_ACCESS_KEY_ID = "your_key",
#'   AWS_SECRET_ACCESS_KEY = "your_secret"
#' )
#' ```
#'
#' **Option 3: External Credentials File**
#'
#' Use AWS credential files at `~/.aws/credentials` and set:
#' ```
#' AWS_PROFILE=your_profile_name
#' ```
#'
#' @section Usage Example:
#'
#' ```r
#' # In your .Renviron file:
#' # AWS_ACCESS_KEY_ID=AKIA...
#' # AWS_SECRET_ACCESS_KEY=wJalr...
#'
#' # In your R script:
#' auth <- gdal_auth_s3()  # Reads from environment
#'
#' job <- gdal_gdal_vector_convert(
#'   input = gdal_vsi_url("vsis3", bucket = "my-bucket", key = "data.shp"),
#'   output_format = "GPKG"
#' ) |>
#'   gdal_with_env(auth) |>
#'   gdal_run()
#' ```
#'
#' @section Why No Function Arguments?:
#'
#' Credentials are **intentionally not accepted as function arguments** because:
#' - ✓ Prevents accidental hardcoding of secrets in R scripts
#' - ✓ Reduces risk of leaking credentials via version control or logs
#' - ✓ Encourages secure credential management via .Renviron
#' - ✓ Follows security best practices (12-factor app)
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
#' `gdal_auth_azure()` reads Azure Blob Storage authentication credentials from
#' environment variables and returns them as a named character vector suitable for
#' use with [gdal_with_env()].
#'
#' **IMPORTANT**: Credentials are read from environment variables (not from function
#' arguments) to prevent accidental exposure in code repositories. This encourages
#' secure credential management via `.Renviron` files or external secret managers.
#'
#' This is the modern, recommended approach for Azure credentials.
#'
#' @param no_sign_request Logical. If `TRUE`, configures public container access
#'   without requiring credentials. Default `FALSE`.
#'
#' @return
#' A named character vector of environment variables for [gdal_with_env()].
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
#' - ✓ Prevents accidental hardcoding of secrets in R scripts
#' - ✓ Reduces risk of leaking credentials via version control or logs
#' - ✓ Encourages secure credential management via .Renviron
#' - ✓ Follows security best practices (12-factor app)
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
#' `gdal_auth_gcs()` reads Google Cloud Storage authentication credentials from
#' environment variables and returns them as a named character vector suitable for
#' use with [gdal_with_env()].
#'
#' **IMPORTANT**: Credentials file path is read from environment variables (not from
#' function arguments) to prevent accidental exposure in code repositories. This
#' encourages secure credential management via `.Renviron` files.
#'
#' @param no_sign_request Logical. If `TRUE`, configures public bucket access
#'   without requiring credentials. Default `FALSE`.
#'
#' @return
#' A named character vector of environment variables for [gdal_with_env()].
#'
#' @section Setting Up Credentials:
#'
#' **Option 1: Service Account JSON File (Recommended)**
#'
#' 1. Download JSON credentials from Google Cloud Console
#' 2. Save to a secure location (e.g., `~/.gcp/credentials.json`)
#' 3. Add to your `~/.Renviron` or project `.Renviron`:
#' ```
#' GOOGLE_APPLICATION_CREDENTIALS=~/.gcp/credentials.json
#' ```
#' 4. Restart R or run `readRenviron("~/.Renviron")`
#'
#' **Option 2: Using gcloud CLI (Alternative)**
#'
#' Set up credentials via:
#' ```bash
#' gcloud auth application-default login
#' ```
#'
#' This automatically sets `GOOGLE_APPLICATION_CREDENTIALS` for you.
#'
#' @section Usage Example:
#'
#' ```r
#' # In your .Renviron file:
#' # GOOGLE_APPLICATION_CREDENTIALS=~/.gcp/credentials.json
#'
#' # In your R script:
#' auth <- gdal_auth_gcs()  # Reads from environment
#'
#' job <- gdal_gdal_vector_convert(
#'   input = gdal_vsi_url("vsigs", bucket = "my-bucket", path = "data.shp"),
#'   output_format = "GPKG"
#' ) |>
#'   gdal_with_env(auth) |>
#'   gdal_run()
#' ```
#'
#' @section Why No Function Arguments?:
#'
#' Credentials are **intentionally not accepted as function arguments** because:
#' - ✓ Prevents accidental hardcoding of secrets in R scripts
#' - ✓ Reduces risk of leaking credentials via version control or logs
#' - ✓ Encourages secure credential management via .Renviron
#' - ✓ Follows security best practices (12-factor app)
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
#' `gdal_auth_oss()` reads Alibaba Cloud OSS authentication credentials from
#' environment variables and returns them as a named character vector suitable for
#' use with [gdal_with_env()].
#'
#' **IMPORTANT**: Credentials are read from environment variables (not from function
#' arguments) to prevent accidental exposure in code repositories. This encourages
#' secure credential management via `.Renviron` files.
#'
#' @param no_sign_request Logical. If `TRUE`, configures public bucket access
#'   without requiring credentials. Default `FALSE`.
#'
#' @return
#' A named character vector of environment variables for [gdal_with_env()].
#'
#' @section Setting Up Credentials:
#'
#' Add to your `~/.Renviron` or project `.Renviron`:
#' ```
#' OSS_ENDPOINT=http://oss-cn-hangzhou.aliyuncs.com
#' OSS_ACCESS_KEY_ID=your_access_key_id
#' OSS_SECRET_ACCESS_KEY=your_secret_access_key
#' OSS_SESSION_TOKEN=optional_session_token
#' ```
#'
#' Then restart R or run `readRenviron("~/.Renviron")`.
#'
#' @section Usage Example:
#'
#' ```r
#' # In your .Renviron file:
#' # OSS_ENDPOINT=http://oss-cn-hangzhou.aliyuncs.com
#' # OSS_ACCESS_KEY_ID=AKIA...
#' # OSS_SECRET_ACCESS_KEY=...
#'
#' # In your R script:
#' auth <- gdal_auth_oss()  # Reads from environment
#'
#' job <- gdal_gdal_vector_convert(
#'   input = gdal_vsi_url("vsioss", bucket = "my-bucket", path = "data.shp"),
#'   output_format = "GPKG"
#' ) |>
#'   gdal_with_env(auth) |>
#'   gdal_run()
#' ```
#'
#' @section Why No Function Arguments?:
#'
#' Credentials are **intentionally not accepted as function arguments** because:
#' - ✓ Prevents accidental hardcoding of secrets in R scripts
#' - ✓ Reduces risk of leaking credentials via version control or logs
#' - ✓ Encourages secure credential management via .Renviron
#' - ✓ Follows security best practices (12-factor app)
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
#' `gdal_auth_swift()` reads OpenStack Swift authentication credentials from
#' environment variables and returns them as a named character vector suitable for
#' use with [gdal_with_env()].
#'
#' **IMPORTANT**: Credentials are read from environment variables (not from function
#' arguments) to prevent accidental exposure in code repositories. This encourages
#' secure credential management via `.Renviron` files.
#'
#' Supports both Auth V1 and Keystone V3 authentication.
#'
#' @param auth_version Character string. Either `"1"` for Auth V1 or `"3"` for
#'   Keystone V3. Default `"3"`.
#'
#' @return
#' A named character vector of environment variables for [gdal_with_env()].
#'
#' @section Setting Up Credentials (Auth V1):
#'
#' Add to your `~/.Renviron` or project `.Renviron`:
#' ```
#' SWIFT_AUTH_V1_URL=http://swift.example.com/auth/v1.0
#' SWIFT_USER=username
#' SWIFT_KEY=password
#' ```
#'
#' @section Setting Up Credentials (Keystone V3):
#'
#' Add to your `~/.Renviron` or project `.Renviron`:
#' ```
#' OS_AUTH_URL=http://keystone.example.com:5000/v3
#' OS_USERNAME=username
#' OS_PASSWORD=password
#' OS_PROJECT_NAME=projectname
#' OS_PROJECT_DOMAIN_NAME=default
#' OS_IDENTITY_API_VERSION=3
#' ```
#'
#' @section Usage Example:
#'
#' ```r
#' # In your .Renviron file (Keystone V3):
#' # OS_AUTH_URL=http://keystone.example.com:5000/v3
#' # OS_USERNAME=myuser
#' # OS_PASSWORD=mypass
#' # OS_PROJECT_NAME=myproject
#'
#' # In your R script:
#' auth <- gdal_auth_swift(auth_version = "3")  # Reads from environment
#'
#' job <- gdal_gdal_vector_convert(
#'   input = gdal_vsi_url("vsiswift", container = "data", path = "file.shp"),
#'   output_format = "GPKG"
#' ) |>
#'   gdal_with_env(auth) |>
#'   gdal_run()
#' ```
#'
#' @section Why No Function Arguments?:
#'
#' Credentials are **intentionally not accepted as function arguments** because:
#' - ✓ Prevents accidental hardcoding of secrets in R scripts
#' - ✓ Reduces risk of leaking credentials via version control or logs
#' - ✓ Encourages secure credential management via .Renviron
#' - ✓ Follows security best practices (12-factor app)
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
