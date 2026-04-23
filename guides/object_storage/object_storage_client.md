# Object Storage Client

Oracle Cloud Infrastructure (OCI) Object Storage is a highly scalable, durable internet-scale storage platform that allows you to store and retrieve any amount of unstructured data from anywhere. It is designed for 99.999999999% (eleven-nines) data durability and provides features such as versioning, lifecycle policies, and pre-authenticated URLs.

Common use cases include:

- Storing and serving binary assets (images, videos, documents)
- Data lake and analytics file storage
- Backup and archival
- Distributing content via pre-authenticated requests (PARs)
- Multipart uploads for large objects

The `ObjectStorageClient` module provides a clean interface for the most common OCI Object Storage operations.

## Create Object Storage Client

```elixir
config = ExOciSdk.Config.from_file!("~/.oci/config")
client = ExOciSdk.Client.create!(config)

os_client = ExOciSdk.ObjectStorage.ObjectStorageClient.create(client)
```

You can override the default endpoint (useful for non-commercial realms):

```elixir
os_client = ExOciSdk.ObjectStorage.ObjectStorageClient.create(client,
  service_endpoint: "https://objectstorage.us-gov-ashburn-1.oraclegovcloud.com"
)
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.create/2`

## Core Features

### Uploading Objects

Upload any binary content to a bucket. The SDK will not JSON-encode the body when `content_type` is not `"application/json"`:

```elixir
namespace = "my-namespace"
bucket = "my-bucket"

# Upload a binary file
{:ok, content} = File.read("/path/to/photo.jpg")

{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.put_object(
  os_client,
  namespace,
  bucket,
  "images/2026/photo.jpg",
  content,
  content_type: "image/jpeg",
  opc_meta: %{"photographer" => "Alice", "location" => "São Paulo"}
)

etag = response.metadata["etag"]
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.put_object/6`

### Downloading Objects

Download an object. For non-JSON content types the raw binary is returned in `response.data`. All response headers (content-type, etag, content-length, opc-meta-*, etc.) are available in `response.metadata`:

```elixir
{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.get_object(
  os_client,
  namespace,
  bucket,
  "images/2026/photo.jpg"
)

binary = response.data
content_type = response.metadata["content-type"]
```

Download a specific byte range:

```elixir
{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.get_object(
  os_client,
  namespace,
  bucket,
  "large-file.bin",
  range: "bytes=0-1048575"
)
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.get_object/5`

### Listing Objects

List objects in a bucket with optional prefix, pagination, and delimiter support:

```elixir
{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.list_objects(
  os_client,
  namespace,
  bucket,
  prefix: "images/2026/",
  limit: 100,
  delimiter: "/"
)

objects = response.data["objects"]
next_page = response.data["next_start_with"]
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.list_objects/4`

### Deleting Objects

Delete a single object (returns HTTP 204):

```elixir
{:ok, _response} = ExOciSdk.ObjectStorage.ObjectStorageClient.delete_object(
  os_client,
  namespace,
  bucket,
  "old-file.txt"
)
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.delete_object/5`

### Batch Deleting Objects

Delete multiple objects in a single request. The response includes `"deleted"` and `"failed"` arrays:

```elixir
batch_input = %{
  objects: [
    %{object_name: "tmp/file1.txt"},
    %{object_name: "tmp/file2.txt"},
    %{object_name: "tmp/file3.txt", if_match: "etag-xyz"}
  ]
}

{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.batch_delete_objects(
  os_client,
  namespace,
  bucket,
  batch_input
)

deleted = response.data["deleted"]
failed  = response.data["failed"]
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.batch_delete_objects/5`

### Retrieving Object Metadata

Use `get_object_metadata/5` to perform an HTTP HEAD request. No body is returned; all metadata is in `response.metadata`:

```elixir
{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.get_object_metadata(
  os_client,
  namespace,
  bucket,
  "report.pdf"
)

etag           = response.metadata["etag"]
content_length = response.metadata["content-length"]
author         = response.metadata["opc-meta-author"]
storage_tier   = response.metadata["storage-tier"]
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.get_object_metadata/5`

### Multipart Uploads

For objects larger than a few hundred MB it is best to split the upload into parts. The typical flow is:

1. **Create** the multipart upload to obtain an `upload_id`
2. **Upload parts** out-of-band (e.g. using the pre-authenticated URL, the OCI CLI, or by calling the REST API for each part directly)
3. **Commit** the multipart upload with the list of parts and their ETags

```elixir
# 1. Initiate the multipart upload
{:ok, init_response} = ExOciSdk.ObjectStorage.ObjectStorageClient.create_multipart_upload(
  os_client,
  namespace,
  bucket,
  %{
    object: "large-video.mp4",
    content_type: "video/mp4"
  }
)

upload_id = init_response.data["upload_id"]

# 2. Upload parts (out of band — the SDK does not yet expose UploadPart directly)
#    Each part returns an ETag header you must record.
part_etags = [
  %{part_num: 1, etag: "etag-part-1"},
  %{part_num: 2, etag: "etag-part-2"},
  %{part_num: 3, etag: "etag-part-3"}
]

# 3. Commit the multipart upload
{:ok, commit_response} = ExOciSdk.ObjectStorage.ObjectStorageClient.commit_multipart_upload(
  os_client,
  namespace,
  bucket,
  "large-video.mp4",
  upload_id,
  %{parts_to_commit: part_etags}
)

final_etag = commit_response.metadata["etag"]
```

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.create_multipart_upload/5` and
`ExOciSdk.ObjectStorage.ObjectStorageClient.commit_multipart_upload/7`

### Pre-Authenticated Requests (PARs)

PARs allow temporary, URL-based access to a bucket or specific object without requiring OCI credentials. The response `uri` field contains the URL to share:

```elixir
par_input = %{
  name: "download-report-link",
  access_type: "ObjectRead",
  time_expires: "2026-12-31T23:59:59Z",
  object_name: "reports/q4-2025.pdf"
}

{:ok, response} = ExOciSdk.ObjectStorage.ObjectStorageClient.create_preauthenticated_request(
  os_client,
  namespace,
  bucket,
  par_input
)

par_uri = response.data["uri"]
# Share this URL — it grants read access until time_expires
```

Valid `access_type` values: `"ObjectRead"`, `"ObjectWrite"`, `"ObjectReadWrite"`,
`"AnyObjectRead"`, `"AnyObjectWrite"`, `"AnyObjectReadWrite"`.

see more details in `ExOciSdk.ObjectStorage.ObjectStorageClient.create_preauthenticated_request/5`

## Configuration Options

### Client Creation Options

- `service_endpoint`: Custom service endpoint URL. Useful for non-commercial OCI realms (GovCloud, sovereign regions) whose hostname differs from `objectstorage.{region}.oraclecloud.com`.

### Common Operation Options

- `opc_request_id`: Custom request identifier for tracing and debugging

### Object name encoding

Object names may contain `/` as a path separator and arbitrary Unicode. The SDK percent-encodes unsafe characters automatically via `URI.encode/1`, preserving `/` so that logical path hierarchies work as expected.

## Response Format

All operations return:

- `{:ok, response}` on success
- `{:error, reason}` on failure

The `response` map contains:

- `data`: Parsed response body (JSON responses are automatically camelCase → snake_case converted; binary responses returned as-is; HEAD responses return `nil`)
- `metadata`: Map with at minimum `opc_request_id` plus any additional headers configured via the response policy (e.g. `etag`, `last-modified`, `content-type`)

## Error Handling

Always pattern-match on the return value:

```elixir
case ExOciSdk.ObjectStorage.ObjectStorageClient.get_object(os_client, namespace, bucket, "file.txt") do
  {:ok, response} ->
    process(response.data)

  {:error, %{error: body, metadata: meta}} ->
    Logger.error("Object Storage error: #{inspect(body)}, request_id=#{meta[:opc_request_id]}")
end
```
