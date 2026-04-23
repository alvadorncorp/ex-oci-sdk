# Copyright 2025 Alan Franzin. Licensed under Apache-2.0.

defmodule ExOciSdk.ObjectStorage.ObjectStorageClient do
  @moduledoc """
  Client for interacting with OCI Object Storage service.

  This module handles object-level operations for OCI Object Storage, including:

  - Uploading objects (`put_object/6`)
  - Downloading objects (`get_object/4`)
  - Deleting objects (`delete_object/4`)
  - Listing objects (`list_objects/3`)
  - Retrieving object metadata (`get_object_metadata/4`)
  - Initiating multipart uploads (`create_multipart_upload/4`)
  - Committing multipart uploads (`commit_multipart_upload/7`)
  - Creating pre-authenticated requests (`create_preauthenticated_request/4`)
  - Batch deleting objects (`batch_delete_objects/4`)
  """

  alias ExOciSdk.{Client, Request, RequestBuilder, ResponsePolicy}
  alias ExOciSdk.ObjectStorage.Types
  alias ExOciSdk.Response.Types, as: ResponseTypes

  defstruct [
    :client,
    :service_endpoint
  ]

  @typedoc """
  Object Storage client structure.

  * `:client` - The base OCI client instance, see `t:ExOciSdk.Client.t/0`
  * `:service_endpoint` - Optional custom service endpoint URL
  """
  @type t :: %__MODULE__{
          client: Client.t(),
          service_endpoint: String.t() | nil
        }

  @doc """
  Creates a new ObjectStorageClient instance.

  ## Parameters

    * `client` - Base SDK client, see `t:ExOciSdk.Client.t/0`
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.object_storage_client_create_opts/0`
  """
  @spec create(Client.t(), Types.object_storage_client_create_opts()) :: t()
  def create(%Client{} = client, opts \\ []) do
    %__MODULE__{
      client: client,
      service_endpoint: Keyword.get(opts, :service_endpoint, nil)
    }
  end

  @doc """
  Returns default service configuration settings `t:ExOciSdk.ObjectStorage.Types.service_settings/0`.
  """
  @spec service_settings() :: Types.service_settings()
  def service_settings do
    %{
      service_endpoint: "https://objectstorage.{region}.oraclecloud.com",
      content_type: "application/json",
      accept: "application/json"
    }
  end

  @doc """
  Uploads an object to a bucket.

  The body may be any binary (file contents, iodata, etc.). The `content_type` option
  controls the `Content-Type` header; it defaults to `"application/octet-stream"` so the
  body is never JSON-encoded by the SDK.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `object_name` - Object name (may include `/` as path separator)
    * `body` - Object contents as binary or iodata
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.put_object_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.metadata` contains `etag`, `last-modified`, and `version-id` headers.
    * `{:error, reason}` - On failure
  """
  @spec put_object(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.object_name(),
          iodata(),
          Types.put_object_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def put_object(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        object_name,
        body,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    RequestBuilder.new(
      :put,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/o/#{encode_object(object_name)}"
    )
    |> RequestBuilder.with_headers(%{
      "content-type" => content_type,
      "content-language" => Keyword.get(opts, :content_language),
      "content-encoding" => Keyword.get(opts, :content_encoding),
      "content-disposition" => Keyword.get(opts, :content_disposition),
      "cache-control" => Keyword.get(opts, :cache_control),
      "content-md5" => Keyword.get(opts, :content_md5),
      "if-match" => Keyword.get(opts, :if_match),
      "if-none-match" => Keyword.get(opts, :if_none_match),
      "storage-tier" => Keyword.get(opts, :storage_tier),
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> maybe_add_meta_headers(Keyword.get(opts, :opc_meta, %{}))
    |> RequestBuilder.with_body(body)
    |> RequestBuilder.with_response_policy(
      ResponsePolicy.new()
      |> ResponsePolicy.with_headers_to_extract([
        "etag",
        "last-modified",
        "version-id",
        "opc-content-md5"
      ])
    )
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Downloads an object from a bucket.

  For JSON objects the SDK returns a parsed map; for all other content types
  (binaries, text, etc.) the raw binary is returned in `response.data`.
  All response headers are available in `response.metadata`.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `object_name` - Object name (may include `/` as path separator)
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.get_object_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` contains the object body.
    * `{:error, reason}` - On failure
  """
  @spec get_object(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.object_name(),
          Types.get_object_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def get_object(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        object_name,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :get,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/o/#{encode_object(object_name)}"
    )
    |> RequestBuilder.with_headers(%{
      "range" => Keyword.get(opts, :range),
      "if-match" => Keyword.get(opts, :if_match),
      "if-none-match" => Keyword.get(opts, :if_none_match),
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_query("versionId", Keyword.get(opts, :version_id))
    |> RequestBuilder.with_response_policy(
      ResponsePolicy.new()
      |> ResponsePolicy.with_headers_to_extract(:all)
    )
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Deletes an object from a bucket.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `object_name` - Object name (may include `/` as path separator)
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.delete_object_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` is `nil` (HTTP 204).
    * `{:error, reason}` - On failure
  """
  @spec delete_object(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.object_name(),
          Types.delete_object_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def delete_object(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        object_name,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :delete,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/o/#{encode_object(object_name)}"
    )
    |> RequestBuilder.with_headers(%{
      "if-match" => Keyword.get(opts, :if_match),
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_query("versionId", Keyword.get(opts, :version_id))
    |> RequestBuilder.with_response_policy(
      ResponsePolicy.new()
      |> ResponsePolicy.with_headers_to_extract(["last-modified", "version-id"])
    )
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Lists objects in a bucket.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.list_objects_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` is a map with `"objects"` key.
    * `{:error, reason}` - On failure
  """
  @spec list_objects(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.list_objects_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def list_objects(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :get,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/o"
    )
    |> RequestBuilder.with_headers(%{
      "content-type" => settings.content_type,
      "accept" => settings.accept,
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_querys(%{
      "prefix" => Keyword.get(opts, :prefix),
      "start" => Keyword.get(opts, :start),
      "end" => Keyword.get(opts, :end_),
      "limit" => Keyword.get(opts, :limit),
      "delimiter" => Keyword.get(opts, :delimiter),
      "fields" => Keyword.get(opts, :fields),
      "startAfter" => Keyword.get(opts, :start_after)
    })
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Retrieves object metadata via an HTTP HEAD request.

  No body is returned. All object headers (etag, content-type, content-length,
  last-modified, storage-tier, opc-meta-* user metadata, etc.) are available
  in `response.metadata`.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `object_name` - Object name (may include `/` as path separator)
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.get_object_metadata_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` is `nil`, all metadata in `response.metadata`.
    * `{:error, reason}` - On failure
  """
  @spec get_object_metadata(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.object_name(),
          Types.get_object_metadata_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def get_object_metadata(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        object_name,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :head,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/o/#{encode_object(object_name)}"
    )
    |> RequestBuilder.with_headers(%{
      "if-match" => Keyword.get(opts, :if_match),
      "if-none-match" => Keyword.get(opts, :if_none_match),
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_query("versionId", Keyword.get(opts, :version_id))
    |> RequestBuilder.with_response_policy(
      ResponsePolicy.new()
      |> ResponsePolicy.with_headers_to_extract(:all)
    )
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Initiates a multipart upload, returning an `uploadId` used in subsequent part uploads and commit.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `create_multipart_upload_input` - Upload details, see `t:ExOciSdk.ObjectStorage.Types.create_multipart_upload_input/0`
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.create_multipart_upload_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` contains the upload details including `upload_id`.
    * `{:error, reason}` - On failure
  """
  @spec create_multipart_upload(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.create_multipart_upload_input(),
          Types.create_multipart_upload_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def create_multipart_upload(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        create_multipart_upload_input,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :post,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/u"
    )
    |> RequestBuilder.with_headers(%{
      "content-type" => settings.content_type,
      "accept" => settings.accept,
      "if-match" => Keyword.get(opts, :if_match),
      "if-none-match" => Keyword.get(opts, :if_none_match),
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_body(create_multipart_upload_input)
    |> RequestBuilder.with_response_policy(
      ResponsePolicy.new()
      |> ResponsePolicy.with_headers_to_extract(["etag", "opc-multipart-md5"])
    )
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Commits a multipart upload by specifying which parts to include in the final object.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `object_name` - Object name of the multipart upload
    * `upload_id` - The upload ID returned by `create_multipart_upload/5`
    * `commit_multipart_upload_input` - Parts to commit, see `t:ExOciSdk.ObjectStorage.Types.commit_multipart_upload_input/0`
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.commit_multipart_upload_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.metadata` contains `etag`, `last-modified`, `opc-multipart-md5`.
    * `{:error, reason}` - On failure
  """
  @spec commit_multipart_upload(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.object_name(),
          String.t(),
          Types.commit_multipart_upload_input(),
          Types.commit_multipart_upload_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def commit_multipart_upload(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        object_name,
        upload_id,
        commit_multipart_upload_input,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :post,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/u/#{encode_object(object_name)}"
    )
    |> RequestBuilder.with_headers(%{
      "content-type" => settings.content_type,
      "accept" => settings.accept,
      "if-match" => Keyword.get(opts, :if_match),
      "if-none-match" => Keyword.get(opts, :if_none_match),
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_query("uploadId", upload_id)
    |> RequestBuilder.with_body(commit_multipart_upload_input)
    |> RequestBuilder.with_response_policy(
      ResponsePolicy.new()
      |> ResponsePolicy.with_headers_to_extract([
        "etag",
        "last-modified",
        "version-id",
        "opc-multipart-md5"
      ])
    )
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Creates a pre-authenticated request (PAR) that grants temporary, URL-based access
  to a bucket or object without requiring OCI credentials.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `create_preauthenticated_request_input` - PAR details, see `t:ExOciSdk.ObjectStorage.Types.create_preauthenticated_request_input/0`
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.create_preauthenticated_request_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` contains the PAR details including the access `uri`.
    * `{:error, reason}` - On failure
  """
  @spec create_preauthenticated_request(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.create_preauthenticated_request_input(),
          Types.create_preauthenticated_request_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def create_preauthenticated_request(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        create_preauthenticated_request_input,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :post,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/p"
    )
    |> RequestBuilder.with_headers(%{
      "content-type" => settings.content_type,
      "accept" => settings.accept,
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_body(create_preauthenticated_request_input)
    |> Request.execute(object_storage_client.client)
  end

  @doc """
  Deletes multiple objects from a bucket in a single request.

  The response includes `"deleted"` and `"failed"` arrays. When `is_skip_deleted_result`
  is `true`, already-deleted objects are omitted from the `"deleted"` array.

  ## Parameters

    * `object_storage_client` - Object Storage client instance `t:t/0`
    * `namespace_name` - OCI namespace name
    * `bucket_name` - Target bucket name
    * `batch_delete_objects_input` - Objects to delete, see `t:ExOciSdk.ObjectStorage.Types.batch_delete_objects_input/0`
    * `opts` - Options list, see `t:ExOciSdk.ObjectStorage.Types.batch_delete_objects_opts/0`

  ## Returns

    * `{:ok, response}` - On success. `response.data` contains `"deleted"` and `"failed"` arrays.
    * `{:error, reason}` - On failure
  """
  @spec batch_delete_objects(
          t(),
          Types.namespace_name(),
          Types.bucket_name(),
          Types.batch_delete_objects_input(),
          Types.batch_delete_objects_opts()
        ) ::
          {:ok, ResponseTypes.response_success()} | {:error, ResponseTypes.response_error()}
  def batch_delete_objects(
        %__MODULE__{} = object_storage_client,
        namespace_name,
        bucket_name,
        batch_delete_objects_input,
        opts \\ []
      ) do
    settings = service_settings()
    service_endpoint = object_storage_client.service_endpoint || settings.service_endpoint

    RequestBuilder.new(
      :post,
      service_endpoint,
      "/n/#{namespace_name}/b/#{bucket_name}/actions/batchDeleteObjects"
    )
    |> RequestBuilder.with_headers(%{
      "content-type" => settings.content_type,
      "accept" => settings.accept,
      "opc-request-id" => Keyword.get(opts, :opc_request_id)
    })
    |> RequestBuilder.with_body(batch_delete_objects_input)
    |> Request.execute(object_storage_client.client)
  end

  @spec encode_object(String.t()) :: String.t()
  defp encode_object(object_name) do
    URI.encode(object_name)
  end

  @spec maybe_add_meta_headers(RequestBuilder.t(), %{String.t() => String.t()}) ::
          RequestBuilder.t()
  defp maybe_add_meta_headers(request, meta) when map_size(meta) == 0, do: request

  defp maybe_add_meta_headers(request, meta) do
    Enum.reduce(meta, request, fn {key, value}, acc ->
      RequestBuilder.with_header(acc, "opc-meta-#{key}", value)
    end)
  end
end
