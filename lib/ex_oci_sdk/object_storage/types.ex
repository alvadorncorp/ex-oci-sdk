# Copyright 2025 Alan Franzin. Licensed under Apache-2.0.

defmodule ExOciSdk.ObjectStorage.Types do
  @moduledoc """
  Defines types used by the Object Storage Client.
  """

  @typedoc "OCI namespace name."
  @type namespace_name :: String.t()

  @typedoc "Bucket name within a namespace."
  @type bucket_name :: String.t()

  @typedoc "Object name within a bucket. May contain `/` as path separator."
  @type object_name :: String.t()

  @typedoc "Request identifier used for tracing and debugging purposes."
  @type opc_request_id :: String.t()

  @typedoc """
  Default Object Storage service settings.

  * `:service_endpoint` - Default OCI service endpoint
  * `:content_type` - Default content type for JSON requests
  * `:accept` - Default accept header for requests
  """
  @type service_settings :: %{
          service_endpoint: String.t(),
          content_type: String.t(),
          accept: String.t()
        }

  @typedoc """
  Options for creating a new ObjectStorageClient.

  * `:service_endpoint` - Custom service endpoint URL (useful for realm-specific domains)
  """
  @type object_storage_client_create_opts :: [
          service_endpoint: String.t()
        ]

  @typedoc """
  Default options available for most Object Storage operations.

  * `:opc_request_id` - Custom request identifier for tracing
  """
  @type object_storage_default_opts :: [
          opc_request_id: opc_request_id()
        ]

  @typedoc """
  Options for uploading an object (PutObject).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:content_type` - MIME type of the object (defaults to `"application/octet-stream"`)
  * `:content_language` - Content language of the object
  * `:content_encoding` - Content encoding of the object
  * `:content_disposition` - Content disposition of the object
  * `:cache_control` - Cache control directive
  * `:content_md5` - Base-64 MD5 hash of the object body for integrity check
  * `:if_match` - Perform only if ETag matches
  * `:if_none_match` - Perform only if ETag does not match
  * `:storage_tier` - Storage tier (e.g. `"Standard"`, `"InfrequentAccess"`, `"Archive"`)
  * `:opc_meta` - Map of user-defined metadata key/value pairs (sent as `opc-meta-{key}` headers)
  """
  @type put_object_opts :: [
          opc_request_id: opc_request_id(),
          content_type: String.t(),
          content_language: String.t(),
          content_encoding: String.t(),
          content_disposition: String.t(),
          cache_control: String.t(),
          content_md5: String.t(),
          if_match: String.t(),
          if_none_match: String.t(),
          storage_tier: String.t(),
          opc_meta: %{String.t() => String.t()}
        ]

  @typedoc """
  Options for downloading an object (GetObject).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:version_id` - Specific object version to retrieve
  * `:range` - Byte range to retrieve (e.g. `"bytes=0-1023"`)
  * `:if_match` - Retrieve only if ETag matches
  * `:if_none_match` - Retrieve only if ETag does not match
  """
  @type get_object_opts :: [
          opc_request_id: opc_request_id(),
          version_id: String.t(),
          range: String.t(),
          if_match: String.t(),
          if_none_match: String.t()
        ]

  @typedoc """
  Options for deleting an object (DeleteObject).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:version_id` - Specific object version to delete
  * `:if_match` - Delete only if ETag matches
  """
  @type delete_object_opts :: [
          opc_request_id: opc_request_id(),
          version_id: String.t(),
          if_match: String.t()
        ]

  @typedoc """
  Options for listing objects in a bucket (ListObjects).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:prefix` - Filters results to objects whose names begin with this prefix
  * `:start` - Object name from which to start the listing
  * `:end_` - Object name at which to stop the listing (exclusive)
  * `:limit` - Maximum number of objects to return
  * `:delimiter` - When set, groups object names up to the first occurrence
  * `:fields` - Comma-separated list of fields to include in the response
  * `:start_after` - Returns objects after this name (for pagination)
  """
  @type list_objects_opts :: [
          opc_request_id: opc_request_id(),
          prefix: String.t(),
          start: String.t(),
          end_: String.t(),
          limit: pos_integer(),
          delimiter: String.t(),
          fields: String.t(),
          start_after: String.t()
        ]

  @typedoc """
  Options for retrieving object metadata via HEAD (GetObjectMetadata).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:version_id` - Specific object version to retrieve metadata for
  * `:if_match` - Retrieve only if ETag matches
  * `:if_none_match` - Retrieve only if ETag does not match
  """
  @type get_object_metadata_opts :: [
          opc_request_id: opc_request_id(),
          version_id: String.t(),
          if_match: String.t(),
          if_none_match: String.t()
        ]

  @typedoc """
  Options for initiating a multipart upload (CreateMultipartUpload).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:if_match` - Initiate only if ETag matches
  * `:if_none_match` - Initiate only if ETag does not match (use `"*"` to fail if object exists)
  """
  @type create_multipart_upload_opts :: [
          opc_request_id: opc_request_id(),
          if_match: String.t(),
          if_none_match: String.t()
        ]

  @typedoc """
  Body for initiating a multipart upload (CreateMultipartUpload).

  * `object` - The object name in the bucket (required)
  * `content_type` - MIME type to set on the final object
  * `content_language` - Content language of the final object
  * `content_encoding` - Content encoding of the final object
  * `content_disposition` - Content disposition of the final object
  * `cache_control` - Cache control directive for the final object
  * `storage_tier` - Storage tier (e.g. `"Standard"`, `"InfrequentAccess"`, `"Archive"`)
  * `metadata` - User-defined metadata key/value pairs for the final object
  """
  @type create_multipart_upload_input :: %{
          required(:object) => String.t(),
          optional(:content_type) => String.t(),
          optional(:content_language) => String.t(),
          optional(:content_encoding) => String.t(),
          optional(:content_disposition) => String.t(),
          optional(:cache_control) => String.t(),
          optional(:storage_tier) => String.t(),
          optional(:metadata) => %{String.t() => String.t()}
        }

  @typedoc """
  Options for committing a multipart upload (CommitMultipartUpload).

  * `:opc_request_id` - Custom request identifier for tracing
  * `:if_match` - Commit only if ETag matches
  * `:if_none_match` - Commit only if ETag does not match (use `"*"` to fail if object exists)
  """
  @type commit_multipart_upload_opts :: [
          opc_request_id: opc_request_id(),
          if_match: String.t(),
          if_none_match: String.t()
        ]

  @typedoc """
  Body for committing a multipart upload (CommitMultipartUpload).

  * `parts_to_commit` - List of parts to include in the final object (required). Each entry must have:
    * `part_num` - The part number as returned when the part was uploaded
    * `etag` - The ETag returned when the part was uploaded
  * `parts_to_exclude` - Optional list of part numbers to exclude from the commit
  """
  @type commit_multipart_upload_input :: %{
          required(:parts_to_commit) => [
            %{
              part_num: pos_integer(),
              etag: String.t()
            }
          ],
          optional(:parts_to_exclude) => [pos_integer()]
        }

  @typedoc """
  Options for creating a pre-authenticated request (CreatePreauthenticatedRequest).

  * `:opc_request_id` - Custom request identifier for tracing
  """
  @type create_preauthenticated_request_opts :: [
          opc_request_id: opc_request_id()
        ]

  @typedoc """
  Body for creating a pre-authenticated request.

  * `name` - Friendly name for the pre-authenticated request (required)
  * `access_type` - The type of access granted (required). Valid values:
    `"ObjectRead"`, `"ObjectWrite"`, `"ObjectReadWrite"`,
    `"AnyObjectRead"`, `"AnyObjectWrite"`, `"AnyObjectReadWrite"`
  * `time_expires` - Expiration date in RFC 3339 format, e.g. `"2026-12-31T23:59:59Z"` (required)
  * `object_name` - The object the request applies to (required for object-level access types)
  * `bucket_listing_action` - Whether to allow bucket listing. Valid values: `"Deny"`, `"ListObjects"`
  """
  @type create_preauthenticated_request_input :: %{
          required(:name) => String.t(),
          required(:access_type) => String.t(),
          required(:time_expires) => String.t(),
          optional(:object_name) => String.t(),
          optional(:bucket_listing_action) => String.t()
        }

  @typedoc """
  Options for batch-deleting objects (BatchDeleteObjects).

  * `:opc_request_id` - Custom request identifier for tracing
  """
  @type batch_delete_objects_opts :: [
          opc_request_id: opc_request_id()
        ]

  @typedoc """
  Body for batch-deleting objects (BatchDeleteObjects).

  * `objects` - List of objects to delete (required). Each entry must have:
    * `object_name` - The name of the object to delete (required)
    * `if_match` - Delete this object only if its ETag matches (optional)
  * `is_skip_deleted_result` - When `true`, already-deleted objects are not included in the response
  """
  @type batch_delete_objects_input :: %{
          required(:objects) => [
            %{
              required(:object_name) => String.t(),
              optional(:if_match) => String.t()
            }
          ],
          optional(:is_skip_deleted_result) => boolean()
        }
end
