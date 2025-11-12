#' Set GDAL VSI Handler Authentication
#'
#' @description
#' `set_gdal_auth()` is an S3 generic method for setting up authentication credentials
#' for GDAL VSI handlers. Rather than embedding credentials in `vsi_url()` calls,
#' this function configures environment variables that GDAL reads automatically.
#'
#' This design improves security (credentials are not hardcoded in scripts) and follows
#' GDAL's native architecture. Call this function once per R session before composing
#' or using VSI URLs.
#'
#' @param handler Character string identifying the authentication handler (e.g., "s3",
#'   "azure", "gs"). Dispatches to an S3 method that sets appropriate environment
#'   variables.
#' @param ... Handler-specific authentication arguments. See method documentation.
#'
#' @return
#' Invisibly returns `TRUE` on success. Raises an error if authentication setup fails
#' or required parameters are missing.
#'
#' @section Supported Handlers:
#'
#' - **s3**: AWS S3 and S3-compatible storage
#' - **azure**: Microsoft Azure Blob Storage
#' - **gs**: Google Cloud Storage
#' - **oss**: Alibaba Cloud OSS
#' - **swift_v1**: OpenStack Swift (Auth V1)
#' - **swift_v3**: OpenStack Swift (Keystone V3)
#'
#' @section Security Considerations:
#'
#' - Credentials are stored in R's environment (visible via `Sys.getenv()`). Avoid
#'   saving R sessions containing set credentials to disk.
#' - For production use, consider using credential files or instance metadata instead
#'   of passing credentials directly (see method documentation).
#' - Never hardcode credentials in published scripts.
#'
#' @examples
#' \dontrun{
#' # Set S3 credentials for AWS
#' set_gdal_auth("s3",
#'   access_key_id = "AKIAIOSFODNN7EXAMPLE",
#'   secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
#' )
#'
#' # Now use vsi_url() without credentials
#' url <- vsi_url("vsis3", bucket = "my-bucket", key = "data.tif")
#'
#' # Set Azure credentials
#' set_gdal_auth("azure", connection_string = "DefaultEndpointsProtocol=https;...")
#'
#' # Set GCS credentials from service account file
#' set_gdal_auth("gs", credentials_file = "~/credentials.json")
#' }
#'
#' @export
set_gdal_auth <- function(handler, ...) {
  UseMethod("set_gdal_auth", handler)
}


#' @export
#' @rdname set_gdal_auth
set_gdal_auth.default <- function(handler, ...) {
  rlang::abort(
    c(
      sprintf("No S3 method available for authentication handler '%s'.", handler),
      "i" = "Supported handlers: s3, azure, gs, oss, swift_v1, swift_v3",
      "i" = "See ?set_gdal_auth for detailed usage."
    ),
    class = "gdalcli_unsupported_auth_handler"
  )
}


#' @export
#' @rdname set_gdal_auth
#' @param access_key_id AWS Access Key ID for S3
#' @param secret_access_key AWS Secret Access Key for S3
#' @param session_token Optional AWS session token for temporary credentials
#' @param region Optional AWS region identifier
#' @param no_sign_request For S3 method, allow unsigned (public) bucket access
#' @param connection_string For Azure method, storage connection string
#' @param account For Azure method, storage account name
#' @param access_key For Azure method, storage access key
#' @param sas_token For Azure method, SAS token
#' @param credentials_file For GCS method, path to service account JSON file
#' @param endpoint For OSS method, endpoint URL
#' @param auth_url For Swift method, authentication URL
#' @param username For Swift method, username
#' @param password For Swift method, password
#' @param project_name For Swift method, project name
#' @param project_domain_name For Swift method, project domain
#' @param auth_v1_url For Swift V1 method, auth V1 URL
#' @param user For Swift V1 method, username
#' @param key For Swift V1 method, API key
#'
#' @examples
#' \dontrun{
#' # Permanent credentials
#' set_gdal_auth("s3",
#'   access_key_id = "AKIAIOSFODNN7EXAMPLE",
#'   secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
#' )
#'
#' # Temporary credentials (from STS)
#' set_gdal_auth("s3",
#'   access_key_id = "...",
#'   secret_access_key = "...",
#'   session_token = "...",
#'   region = "us-west-2"
#' )
#'
#' # Public bucket (no authentication)
#' set_gdal_auth("s3", no_sign_request = TRUE)
#' }
set_gdal_auth.s3 <- function(handler, access_key_id = NULL, secret_access_key = NULL,
                               session_token = NULL, region = NULL, no_sign_request = FALSE, ...) {
  if (no_sign_request) {
    Sys.setenv(AWS_NO_SIGN_REQUEST = "YES")
    cli::cli_alert_success("Set AWS_NO_SIGN_REQUEST=YES for public bucket access")
    return(invisible(TRUE))
  }

  if (is.null(access_key_id) || is.null(secret_access_key)) {
    rlang::abort(
      c(
        "S3 authentication requires either:",
        "i" = "access_key_id and secret_access_key (permanent credentials), or",
        "i" = "no_sign_request=TRUE (for public buckets)"
      )
    )
  }

  Sys.setenv(AWS_ACCESS_KEY_ID = access_key_id)
  Sys.setenv(AWS_SECRET_ACCESS_KEY = secret_access_key)

  if (!is.null(session_token)) {
    Sys.setenv(AWS_SESSION_TOKEN = session_token)
  }

  if (!is.null(region)) {
    Sys.setenv(AWS_REGION = region)
  }

  msg <- sprintf(
    "Set AWS credentials for S3 access%s",
    if (!is.null(region)) sprintf(" (region: %s)", region) else ""
  )
  cli::cli_alert_success(msg)

  invisible(TRUE)
}


#' @export
#' @rdname set_gdal_auth
#'
#' @details
#' ## azure: Microsoft Azure Blob Storage
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Authentication Methods (choose exactly one):**
#'
#' 1. **Connection String** (simplest):
#'    ```r
#'    set_gdal_auth("azure", connection_string = "DefaultEndpointsProtocol=https;...")
#'    ```
#'
#' 2. **Account + Access Key**:
#'    ```r
#'    set_gdal_auth("azure", account = "myaccount", access_key = "...")
#'    ```
#'
#' 3. **Account + SAS Token**:
#'    ```r
#'    set_gdal_auth("azure", account = "myaccount", sas_token = "st=2019...")
#'    ```
#'    Note: Leading `?` or `&` and trailing `&` are automatically stripped.
#'
#' 4. **Public Container Access**:
#'    ```r
#'    set_gdal_auth("azure", no_sign_request = TRUE)
#'    ```
#'
#' **Parameters:**
#' - `connection_string`: Character string or NULL. Full connection string from Azure portal.
#' - `account`: Character string or NULL. Storage account name.
#' - `access_key`: Character string or NULL. Account access key.
#' - `sas_token`: Character string or NULL. SAS token (automatically sanitized).
#' - `no_sign_request`: Logical. For public containers. Default FALSE.
#'
#' @examples
#' \dontrun{
#' # Using connection string (recommended)
#' set_gdal_auth("azure",
#'   connection_string = "DefaultEndpointsProtocol=https;AccountName=..."
#' )
#'
#' # Using account and access key
#' set_gdal_auth("azure", account = "myaccount", access_key = "...")
#'
#' # Using SAS token (? and & are auto-stripped)
#' set_gdal_auth("azure", account = "myaccount", sas_token = "?st=2019...")
#' }
set_gdal_auth.azure <- function(handler, connection_string = NULL, account = NULL,
                                 access_key = NULL, sas_token = NULL, no_sign_request = FALSE, ...) {
  # Count how many authentication methods were provided
  methods_provided <- sum(
    !is.null(connection_string),
    (!is.null(account) && !is.null(access_key)),
    (!is.null(account) && !is.null(sas_token)),
    no_sign_request
  )

  if (methods_provided == 0) {
    rlang::abort(
      c(
        "Azure authentication requires exactly one of:",
        "i" = "connection_string, or",
        "i" = "(account + access_key), or",
        "i" = "(account + sas_token), or",
        "i" = "no_sign_request=TRUE"
      )
    )
  }

  if (methods_provided > 1) {
    rlang::abort(
      "Azure authentication requires exactly ONE method; multiple methods were provided."
    )
  }

  if (!is.null(connection_string)) {
    Sys.setenv(AZURE_STORAGE_CONNECTION_STRING = connection_string)
    cli::cli_alert_success("Set Azure Storage authentication via connection string")
  } else if (!is.null(account) && !is.null(access_key)) {
    Sys.setenv(AZURE_STORAGE_ACCOUNT = account)
    Sys.setenv(AZURE_STORAGE_ACCESS_KEY = access_key)
    cli::cli_alert_success(sprintf("Set Azure Storage authentication for account: %s", account))
  } else if (!is.null(account) && !is.null(sas_token)) {
    sas_token <- sanitize_sas_token(sas_token)
    Sys.setenv(AZURE_STORAGE_ACCOUNT = account)
    Sys.setenv(AZURE_STORAGE_SAS_TOKEN = sas_token)
    cli::cli_alert_success(sprintf("Set Azure Storage SAS token authentication for account: %s", account))
  } else if (no_sign_request) {
    Sys.setenv(AZURE_NO_SIGN_REQUEST = "YES")
    cli::cli_alert_success("Set AZURE_NO_SIGN_REQUEST=YES for public container access")
  }

  invisible(TRUE)
}


#' @export
#' @rdname set_gdal_auth
#'
#' @details
#' ## gs: Google Cloud Storage
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Recommended Method: Service Account JSON File**
#'
#' The simplest and most standard way to authenticate is to use a service account
#' credentials file (downloaded from Google Cloud Console).
#'
#' **Parameters:**
#' - `credentials_file`: Character string or NULL. Path to a JSON credentials file
#'   (service account or authorized user). Default NULL.
#' - `no_sign_request`: Logical. For public buckets. Default FALSE.
#'
#' **Environment Variable Set:**
#' - `GOOGLE_APPLICATION_CREDENTIALS` (if credentials_file provided)
#' - `GS_NO_SIGN_REQUEST` (if no_sign_request=TRUE)
#'
#' @examples
#' \dontrun{
#' # Service account (recommended)
#' set_gdal_auth("gs", credentials_file = "~/gcp-credentials.json")
#'
#' # Public bucket
#' set_gdal_auth("gs", no_sign_request = TRUE)
#' }
set_gdal_auth.gs <- function(handler, credentials_file = NULL, no_sign_request = FALSE, ...) {
  methods_provided <- sum(!is.null(credentials_file), no_sign_request)

  if (methods_provided == 0) {
    rlang::abort(
      c(
        "Google Cloud Storage authentication requires:",
        "i" = "credentials_file (path to JSON), or",
        "i" = "no_sign_request=TRUE (for public buckets)"
      )
    )
  }

  if (methods_provided > 1) {
    rlang::abort(
      "GCS authentication requires exactly ONE method; multiple were provided."
    )
  }

  if (!is.null(credentials_file)) {
    if (!file.exists(credentials_file)) {
      rlang::abort(sprintf("Credentials file not found: %s", credentials_file))
    }

    Sys.setenv(GOOGLE_APPLICATION_CREDENTIALS = credentials_file)
    cli::cli_alert_success(sprintf("Set GCS credentials from file: %s", credentials_file))
  } else if (no_sign_request) {
    Sys.setenv(GS_NO_SIGN_REQUEST = "YES")
    cli::cli_alert_success("Set GS_NO_SIGN_REQUEST=YES for public bucket access")
  }

  invisible(TRUE)
}


#' @export
#' @rdname set_gdal_auth
#'
#' @details
#' ## oss: Alibaba Cloud OSS
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Environment Variables Set:**
#' - `OSS_ENDPOINT` (required)
#' - `OSS_ACCESS_KEY_ID`
#' - `OSS_SECRET_ACCESS_KEY`
#' - `OSS_SESSION_TOKEN` (if temporary credentials)
#' - `OSS_NO_SIGN_REQUEST` (if public bucket)
#'
#' **Parameters:**
#' - `endpoint`: Character string. OSS endpoint URL (e.g., "http://oss-us-east-1.aliyuncs.com")
#' - `access_key_id`: Character string or NULL
#' - `secret_access_key`: Character string or NULL
#' - `session_token`: Character string or NULL. For temporary credentials.
#' - `no_sign_request`: Logical. For public buckets. Default FALSE.
#'
#' @examples
#' \dontrun{
#' set_gdal_auth("oss",
#'   endpoint = "http://oss-us-east-1.aliyuncs.com",
#'   access_key_id = "...",
#'   secret_access_key = "..."
#' )
#' }
set_gdal_auth.oss <- function(handler, endpoint = NULL, access_key_id = NULL,
                               secret_access_key = NULL, session_token = NULL,
                               no_sign_request = FALSE, ...) {
  if (no_sign_request) {
    Sys.setenv(OSS_NO_SIGN_REQUEST = "YES")
    cli::cli_alert_success("Set OSS_NO_SIGN_REQUEST=YES for public bucket access")
    return(invisible(TRUE))
  }

  if (is.null(endpoint)) {
    rlang::abort("OSS authentication requires 'endpoint' parameter (required for all methods)")
  }

  if (is.null(access_key_id) || is.null(secret_access_key)) {
    rlang::abort(
      c(
        "OSS authentication requires either:",
        "i" = "access_key_id and secret_access_key, or",
        "i" = "no_sign_request=TRUE"
      )
    )
  }

  Sys.setenv(OSS_ENDPOINT = endpoint)
  Sys.setenv(OSS_ACCESS_KEY_ID = access_key_id)
  Sys.setenv(OSS_SECRET_ACCESS_KEY = secret_access_key)

  if (!is.null(session_token)) {
    Sys.setenv(OSS_SESSION_TOKEN = session_token)
  }

  cli::cli_alert_success(sprintf("Set OSS credentials for endpoint: %s", endpoint))

  invisible(TRUE)
}


#' @export
#' @rdname set_gdal_auth
#'
#' @details
#' ## swift_v3: OpenStack Swift (Keystone V3 Authentication)
#'
#' **GDAL Version:** ≥ 3.0.0
#'
#' **Environment Variables Set:**
#' - `OS_IDENTITY_API_VERSION=3` (required for V3)
#' - `OS_AUTH_URL`
#' - `OS_USERNAME`
#' - `OS_PASSWORD`
#' - `OS_PROJECT_NAME`
#' - `OS_PROJECT_DOMAIN_NAME`
#'
#' **Parameters:**
#' - `auth_url`: Character string. Keystone V3 authentication endpoint
#' - `username`: Character string. OpenStack username
#' - `password`: Character string. OpenStack password
#' - `project_name`: Character string. Project name
#' - `project_domain_name`: Character string. Project domain name. Default "default".
#'
#' @examples
#' \dontrun{
#' set_gdal_auth("swift_v3",
#'   auth_url = "http://keystone.example.com:5000/v3",
#'   username = "user",
#'   password = "pass",
#'   project_name = "admin",
#'   project_domain_name = "Default"
#' )
#' }
set_gdal_auth.swift_v3 <- function(handler, auth_url, username, password, project_name,
                                    project_domain_name = "default", ...) {
  Sys.setenv(OS_IDENTITY_API_VERSION = "3")
  Sys.setenv(OS_AUTH_URL = auth_url)
  Sys.setenv(OS_USERNAME = username)
  Sys.setenv(OS_PASSWORD = password)
  Sys.setenv(OS_PROJECT_NAME = project_name)
  Sys.setenv(OS_PROJECT_DOMAIN_NAME = project_domain_name)

  cli::cli_alert_success(sprintf("Set OpenStack Swift (Keystone v3) authentication for project: %s", project_name))

  invisible(TRUE)
}


#' @export
#' @rdname set_gdal_auth
#'
#' @details
#' ## swift_v1: OpenStack Swift (Auth V1)
#'
#' **GDAL Version:** ≥ 3.0.0
#'
#' **Environment Variables Set:**
#' - `SWIFT_AUTH_V1_URL`
#' - `SWIFT_USER`
#' - `SWIFT_KEY`
#'
#' **Parameters:**
#' - `auth_v1_url`: Character string. Auth V1 endpoint (e.g., "http://swift.example.com/auth/v1.0")
#' - `user`: Character string. Swift user/account
#' - `key`: Character string. Swift key/password
#'
#' @examples
#' \dontrun{
#' set_gdal_auth("swift_v1",
#'   auth_v1_url = "http://swift.example.com/auth/v1.0",
#'   user = "testuser",
#'   key = "testkey"
#' )
#' }
set_gdal_auth.swift_v1 <- function(handler, auth_v1_url, user, key, ...) {
  Sys.setenv(SWIFT_AUTH_V1_URL = auth_v1_url)
  Sys.setenv(SWIFT_USER = user)
  Sys.setenv(SWIFT_KEY = key)

  cli::cli_alert_success("Set OpenStack Swift (Auth v1) credentials")

  invisible(TRUE)
}
