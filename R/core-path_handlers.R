#' Path-Based VSI Handler Methods
#'
#' S3 methods for simple path-based VSI handlers (cloud storage, network, utilities).
#' Each handler corresponds to a GDAL VSI prefix and composes URLs by concatenating
#' path components. These handlers support the `streaming` parameter to toggle between
#' random-access (default, efficient) and streaming-only variants.
#'
#' @keywords internal
#' @name path_handlers


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsis3: AWS S3 and S3-Compatible Storage
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Syntax:** `/vsis3/bucket/key` or `/vsis3_streaming/bucket/key`
#'
#' **Authentication:** Set via environment variables (see [set_gdal_auth()]):
#' - `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
#' - `AWS_SESSION_TOKEN` (for temporary credentials)
#' - `AWS_NO_SIGN_REQUEST=YES` (for public buckets)
#' - `AWS_REGION` (optional)
#'
#' **Parameters:**
#' - `bucket`: S3 bucket name (e.g., "sentinel-pds")
#' - `key`: Object key / path within bucket (e.g., "tiles/10/S/DG/2015/12/7/0/B01.jp2")
#' - `streaming`: Logical. Use `/vsis3_streaming/` for sequential-only access (not recommended
#'   for Cloud Optimized GeoTIFF). Default FALSE.
#' - `validate`: Logical. If TRUE, check that bucket and key are non-empty. Default FALSE.
#'
#' @examples
#' # Public Sentinel-2 data on AWS
#' vsi_url("vsis3",
#'   bucket = "sentinel-pds",
#'   key = "tiles/10/S/DG/2015/12/7/0/B01.jp2"
#' )
#'
#' # Private bucket (requires authentication via set_gdal_auth("s3", ...))
#' vsi_url("vsis3", bucket = "my-private-bucket", key = "data/file.tif")
vsi_url.vsis3 <- function(bucket, key, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    bucket <- validate_path_component(bucket, "bucket", allow_empty = FALSE)
    key <- validate_path_component(key, "key", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsis3", streaming)
  paste0(prefix, bucket, "/", key)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsigs: Google Cloud Storage
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Syntax:** `/vsigs/bucket/key` or `/vsigs_streaming/bucket/key`
#'
#' **Authentication:** Set via environment variables (see [set_gdal_auth()]):
#' - `GOOGLE_APPLICATION_CREDENTIALS` (path to JSON credentials file) - recommended
#' - `GS_OAUTH2_REFRESH_TOKEN` + `GS_OAUTH2_CLIENT_ID` + `GS_OAUTH2_CLIENT_SECRET`
#' - `GS_NO_SIGN_REQUEST=YES` (for public buckets)
#'
#' **Parameters:**
#' - `bucket`: GCS bucket name (e.g., "my_bucket")
#' - `key`: Object key / path within bucket (e.g., "image.tif")
#' - `streaming`: Logical. Use `/vsigs_streaming/` for sequential-only access. Default FALSE.
#' - `validate`: Logical. If TRUE, check that bucket and key are non-empty. Default FALSE.
#'
#' @examples
#' # Public GCS data
#' vsi_url("vsigs", bucket = "gcs-bucket", key = "path/to/file.tif")
vsi_url.vsigs <- function(bucket, key, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    bucket <- validate_path_component(bucket, "bucket", allow_empty = FALSE)
    key <- validate_path_component(key, "key", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsigs", streaming)
  paste0(prefix, bucket, "/", key)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsiaz: Microsoft Azure Blob Storage
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Syntax:** `/vsiaz/container/key` or `/vsiaz_streaming/container/key`
#'
#' **Authentication:** Set via environment variables (see [set_gdal_auth()]):
#' - `AZURE_STORAGE_CONNECTION_STRING` (easiest method)
#' - `AZURE_STORAGE_ACCOUNT` + `AZURE_STORAGE_ACCESS_KEY`
#' - `AZURE_STORAGE_ACCOUNT` + `AZURE_STORAGE_SAS_TOKEN`
#' - `AZURE_NO_SIGN_REQUEST=YES` (for public containers)
#'
#' **Parameters:**
#' - `container`: Azure Blob container name (e.g., "container1")
#' - `key`: Blob key / path within container (e.g., "Points_1.shp")
#' - `streaming`: Logical. Use `/vsiaz_streaming/` for sequential-only access. Default FALSE.
#' - `validate`: Logical. If TRUE, check that container and key are non-empty. Default FALSE.
#'
#' @examples
#' # Azure Blob Storage
#' vsi_url("vsiaz", container = "mycontainer", key = "data/shapefile.shp")
vsi_url.vsiaz <- function(container, key, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    container <- validate_path_component(container, "container", allow_empty = FALSE)
    key <- validate_path_component(key, "key", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsiaz", streaming)
  paste0(prefix, container, "/", key)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsiadls: Microsoft Azure Data Lake Storage Gen2
#'
#' **GDAL Version:** ≥ 3.3.0 (3.6.1+ recommended)
#'
#' **Syntax:** `/vsiadls/filesystem/path/to/file`
#'
#' **Authentication:** Identical to `/vsiaz/` (uses same AZURE_STORAGE_* environment variables)
#'
#' **Parameters:**
#' - `filesystem`: ADLS Gen2 filesystem name
#' - `path`: Hierarchical path to the file
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, check components are non-empty. Default FALSE.
#'
#' @examples
#' # Azure Data Lake Storage Gen2
#' vsi_url("vsiadls", filesystem = "myfs", path = "dir/file.parquet")
vsi_url.vsiadls <- function(filesystem, path, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    filesystem <- validate_path_component(filesystem, "filesystem", allow_empty = FALSE)
    path <- validate_path_component(path, "path", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsiadls", streaming)
  paste0(prefix, filesystem, "/", path)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsioss: Alibaba Cloud Object Storage Service
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Syntax:** `/vsioss/bucket/key` or `/vsioss_streaming/bucket/key`
#'
#' **Authentication:** Set via environment variables (see [set_gdal_auth()]):
#' - `OSS_ENDPOINT` (required, e.g., "http://oss-us-east-1.aliyuncs.com")
#' - `OSS_ACCESS_KEY_ID` + `OSS_SECRET_ACCESS_KEY`
#' - `OSS_SESSION_TOKEN` (for temporary credentials)
#' - `OSS_NO_SIGN_REQUEST=YES` (for public buckets)
#'
#' **Parameters:**
#' - `bucket`: OSS bucket name
#' - `key`: Object key / path within bucket
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, check components are non-empty. Default FALSE.
#'
#' @examples
#' # Alibaba Cloud OSS
#' vsi_url("vsioss", bucket = "my-bucket", key = "data/file.tif")
vsi_url.vsioss <- function(bucket, key, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    bucket <- validate_path_component(bucket, "bucket", allow_empty = FALSE)
    key <- validate_path_component(key, "key", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsioss", streaming)
  paste0(prefix, bucket, "/", key)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsiswift: OpenStack Swift
#'
#' **GDAL Version:** ≥ 3.0.0 (3.6.1+ recommended)
#'
#' **Syntax:** `/vsiswift/bucket/key` or `/vsiswift_streaming/bucket/key`
#'
#' **Authentication:** Set via environment variables (see [set_gdal_auth()]):
#' - **Keystone V3:** `OS_IDENTITY_API_VERSION=3`, `OS_AUTH_URL`, `OS_USERNAME`, `OS_PASSWORD`,
#'   `OS_PROJECT_NAME`, `OS_PROJECT_DOMAIN_NAME`
#' - **Auth V1:** `SWIFT_AUTH_V1_URL`, `SWIFT_USER`, `SWIFT_KEY`
#'
#' **Parameters:**
#' - `bucket`: Swift container name
#' - `key`: Object key / path within container
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, check components are non-empty. Default FALSE.
#'
#' @examples
#' # OpenStack Swift
#' vsi_url("vsiswift", bucket = "container", key = "data/file.tif")
vsi_url.vsiswift <- function(bucket, key, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    bucket <- validate_path_component(bucket, "bucket", allow_empty = FALSE)
    key <- validate_path_component(key, "key", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsiswift", streaming)
  paste0(prefix, bucket, "/", key)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsicurl: HTTP, HTTPS, FTP
#'
#' **GDAL Version:** ≥ Pre-3.0 (mature in all 3.x versions)
#'
#' **Syntax:** `/vsicurl/http://...` or `/vsicurl/https://...` or `/vsicurl/ftp://...`
#'
#' **Authentication:** Set via environment variables (see [set_gdal_auth()]):
#' - **FTP Basic Auth:** Embed in URL or use environment variables
#' - **HTTP Bearer Token:** `GDAL_HTTP_BEARER`
#' - **Custom Headers:** `GDAL_HTTP_HEADER_FILE` (path to text file with `Key: Value` headers)
#' - **Proxy:** `GDAL_HTTP_PROXY` and `GDAL_HTTP_PROXYUSERPWD`
#'
#' **Parameters:**
#' - `url`: Full URL string (including protocol: http://, https://, or ftp://)
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, check URL is non-empty. Default FALSE.
#'
#' @examples
#' # HTTP(S) URL
#' vsi_url("vsicurl", url = "https://example.com/data/file.tif")
vsi_url.vsicurl <- function(url, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    url <- validate_path_component(url, "url", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsicurl", streaming)
  paste0(prefix, url)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsigzip: GZip-Compressed Files
#'
#' **GDAL Version:** ≥ Pre-3.0 (requires zlib)
#'
#' **Syntax:** `/vsigzip/path/to/file.gz`
#'
#' **Important:** This handler decompresses a single GZip file, exposing the decompressed
#' data stream. It is NOT for reading archives (use `/vsitar/` for TAR.GZ files).
#'
#' **Parameters:**
#' - `path`: Path to the .gz file (local or VSI path)
#' - `streaming`: Ignored (GZip always streams decompression)
#' - `validate`: Logical. If TRUE, check path is non-empty. Default FALSE.
#'
#' @examples
#' # Local gzip file
#' vsi_url("vsigzip", path = "data/file.tif.gz")
#'
#' # Remote gzip file
#' vsi_url("vsigzip", path = "/vsicurl/https://example.com/file.tif.gz")
vsi_url.vsigzip <- function(path, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    path <- validate_path_component(path, "path", allow_empty = FALSE)
  }

  # Note: streaming parameter is ignored for gzip; always uses single path
  paste0("/vsigzip/", path)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsimem: In-Memory Files
#'
#' **GDAL Version:** ≥ Pre-3.0
#'
#' **Syntax:** `/vsimem/filename`
#'
#' **Use Case:** For temporary files, VRTs, or conversions that benefit from memory storage
#' instead of disk I/O.
#'
#' **Parameters:**
#' - `filename`: Arbitrary path/name for the virtual file (e.g., "temp.tif" or "vrt/layer.vrt")
#' - `streaming`: Ignored (memory files are always random-access)
#' - `validate`: Logical. If TRUE, check filename is non-empty. Default FALSE.
#'
#' @examples
#' # Temporary in-memory file
#' vsi_url("vsimem", filename = "temp.tif")
#'
#' # Nested path in memory
#' vsi_url("vsimem", filename = "temp/subdir/layer.vrt")
vsi_url.vsimem <- function(filename, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    filename <- validate_path_component(filename, "filename", allow_empty = FALSE)
  }

  paste0("/vsimem/", filename)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsihdfs: Hadoop HDFS (Native Protocol)
#'
#' **GDAL Version:** ≥ Pre-3.0
#'
#' **Syntax:** `/vsihdfs/hdfs://hostname:port/path/to/file`
#'
#' **Authentication:** Depends on Hadoop cluster configuration (Kerberos, etc.)
#'
#' **Parameters:**
#' - `path`: Full HDFS path (e.g., "hdfs://namenode:8020/data/file.tif")
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, check path is non-empty. Default FALSE.
#'
#' @examples
#' # HDFS path
#' vsi_url("vsihdfs", path = "hdfs://namenode:8020/user/data/file.tif")
vsi_url.vsihdfs <- function(path, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    path <- validate_path_component(path, "path", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsihdfs", streaming)
  paste0(prefix, path)
}


#' @export
#' @rdname vsi_url
#'
#' @details
#' ## vsiwebhdfs: Hadoop WebHDFS (REST API)
#'
#' **GDAL Version:** ≥ Pre-3.0
#'
#' **Syntax:** `/vsiwebhdfs/http://hostname:port/webhdfs/v1/path/to/file`
#'
#' **Authentication:** HTTP-based (same as `/vsicurl/`); see [set_gdal_auth()]
#'
#' **Parameters:**
#' - `url`: Full WebHDFS URL (e.g., "http://namenode:50070/webhdfs/v1/user/data/file.tif")
#' - `streaming`: Logical. Use streaming variant. Default FALSE.
#' - `validate`: Logical. If TRUE, check URL is non-empty. Default FALSE.
#'
#' @examples
#' # WebHDFS path
#' vsi_url("vsiwebhdfs", url = "http://namenode:50070/webhdfs/v1/data/file.tif")
vsi_url.vsiwebhdfs <- function(url, ..., streaming = FALSE, validate = FALSE) {
  if (validate) {
    url <- validate_path_component(url, "url", allow_empty = FALSE)
  }

  prefix <- compose_vsi_prefix("vsiwebhdfs", streaming)
  paste0(prefix, url)
}
