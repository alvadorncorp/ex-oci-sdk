defmodule ExOciSdk.ObjectStorage.ObjectStorageClientTest do
  use ExUnit.Case, async: true

  alias ExOciSdk.{Config, Client, KeyConverter}
  alias ExOciSdk.ObjectStorage.ObjectStorageClient

  import Mox

  setup :verify_on_exit!

  @namespace "my-namespace"
  @bucket "my-bucket"
  @region_endpoint "https://objectstorage.sa-saopaulo-1.oraclecloud.com"

  defp build_client do
    config = Config.from_file!(Path.join(__DIR__, "../../support/config"))

    expect(ExOciSdk.HTTPClientMock, :deps, fn -> [String] end)
    expect(ExOciSdk.JSONMock, :deps, fn -> [String] end)

    Client.create!(config,
      http_client: {ExOciSdk.HTTPClientMock, []},
      json: {ExOciSdk.JSONMock, []}
    )
  end

  describe "create/2" do
    setup do
      %{client: build_client()}
    end

    test "creates client with default options", %{client: client} do
      os_client = ObjectStorageClient.create(client)

      assert os_client.client == client
      assert os_client.service_endpoint == nil
    end

    test "creates client with custom service_endpoint", %{client: client} do
      os_client =
        ObjectStorageClient.create(client, service_endpoint: "https://custom.example.com")

      assert os_client.client == client
      assert os_client.service_endpoint == "https://custom.example.com"
    end
  end

  describe "service_settings/0" do
    test "returns default Object Storage service settings" do
      settings = ObjectStorageClient.service_settings()

      assert settings.service_endpoint == "https://objectstorage.{region}.oraclecloud.com"
      assert settings.content_type == "application/json"
      assert settings.accept == "application/json"
    end
  end

  describe "put_object/6" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "uploads binary body with default options", %{os_client: os_client} do
      body = "hello world"
      object_name = "files/hello.txt"

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, req_body, headers, _opts ->
        assert method == :put
        assert req_body == body
        assert Map.has_key?(headers, "authorization")
        assert Map.get(headers, "content-type") == "application/octet-stream"

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o/#{URI.encode(object_name)}"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [
             {"etag", "etag-abc"},
             {"last-modified", "Mon, 01 Jan 2026 00:00:00 GMT"},
             {"opc-request-id", "req-123"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.put_object(os_client, @namespace, @bucket, object_name, body)

      assert result.data == nil
      assert result.metadata[:opc_request_id] == "req-123"
      assert result.metadata["etag"] == "etag-abc"
      assert result.metadata["last-modified"] == "Mon, 01 Jan 2026 00:00:00 GMT"
    end

    test "uploads with custom content_type and opc_meta headers", %{os_client: os_client} do
      body = "plain text content"
      object_name = "data/notes.txt"

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, req_body, headers, _opts ->
        assert method == :put
        assert req_body == body
        assert Map.get(headers, "content-type") == "text/plain"
        assert Map.get(headers, "opc-meta-owner") == "alice"
        assert Map.get(headers, "opc-meta-env") == "prod"

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o/#{URI.encode(object_name)}"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [
             {"etag", "etag-xyz"},
             {"opc-request-id", "req-456"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.put_object(
                 os_client,
                 @namespace,
                 @bucket,
                 object_name,
                 body,
                 content_type: "text/plain",
                 opc_meta: %{"owner" => "alice", "env" => "prod"},
                 opc_request_id: "req-456"
               )

      assert result.metadata["etag"] == "etag-xyz"
    end

    test "encodes object names with spaces", %{os_client: os_client} do
      object_name = "my folder/my file.txt"

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, url, _body, _headers, _opts ->
        assert url =~ "my%20folder/my%20file.txt"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [{"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.put_object(os_client, @namespace, @bucket, object_name, "data")
    end

    test "returns error on non-2xx response", %{os_client: os_client} do
      error_body = ~s({"code":"NotAuthenticated","message":"Not authenticated"})

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, _url, _body, _headers, _opts ->
        {:ok,
         %{
           status_code: 403,
           body: error_body,
           headers: [{"content-type", "application/json"}, {"opc-request-id", "r"}]
         }}
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn _input, _opts -> %{"code" => "NotAuthenticated"} end)

      assert {:error, _} =
               ObjectStorageClient.put_object(os_client, @namespace, @bucket, "file.txt", "data")
    end

    test "uses custom service_endpoint when set", %{os_client: _} do
      client = build_client()
      custom_endpoint = "https://custom-os.example.com"
      os_client = ObjectStorageClient.create(client, service_endpoint: custom_endpoint)

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, url, _body, _headers, _opts ->
        assert String.starts_with?(url, custom_endpoint)

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [{"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.put_object(os_client, @namespace, @bucket, "file.txt", "data")
    end
  end

  describe "get_object/5" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "downloads binary object with default options", %{os_client: os_client} do
      object_name = "images/photo.png"
      binary_body = <<0, 1, 2, 3, 255>>

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, req_body, headers, _opts ->
        assert method == :get
        assert req_body == ""
        assert Map.has_key?(headers, "authorization")
        refute Map.has_key?(headers, "content-type")

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o/#{URI.encode(object_name)}"

        {:ok,
         %{
           status_code: 200,
           body: binary_body,
           headers: [
             {"content-type", "image/png"},
             {"etag", "etag-img"},
             {"content-length", "5"},
             {"opc-request-id", "req-get-1"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.get_object(os_client, @namespace, @bucket, object_name)

      assert result.data == binary_body
      assert result.metadata[:opc_request_id] == "req-get-1"
      assert result.metadata["etag"] == "etag-img"
      assert result.metadata["content-type"] == "image/png"
    end

    test "sends range and version_id when provided", %{os_client: os_client} do
      object_name = "data.bin"

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :get
        assert Map.get(headers, "range") == "bytes=0-1023"

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o/#{object_name}?versionId=v1"

        {:ok,
         %{
           status_code: 200,
           body: "partial",
           headers: [
             {"content-type", "application/octet-stream"},
             {"opc-request-id", "r"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.get_object(
                 os_client,
                 @namespace,
                 @bucket,
                 object_name,
                 range: "bytes=0-1023",
                 version_id: "v1"
               )

      assert result.data == "partial"
    end

    test "returns error on 404", %{os_client: os_client} do
      error_body = ~s({"code":"ObjectNotFound","message":"Object not found"})

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, _url, _body, _headers, _opts ->
        {:ok,
         %{
           status_code: 404,
           body: error_body,
           headers: [{"content-type", "application/json"}, {"opc-request-id", "r"}]
         }}
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn _input, _opts -> %{"code" => "ObjectNotFound"} end)

      assert {:error, _} =
               ObjectStorageClient.get_object(os_client, @namespace, @bucket, "missing.txt")
    end
  end

  describe "delete_object/5" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "deletes object with default options (204 no content)", %{os_client: os_client} do
      object_name = "to-delete.txt"

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, req_body, headers, _opts ->
        assert method == :delete
        assert req_body == ""
        assert Map.has_key?(headers, "authorization")
        assert url == "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o/#{object_name}"

        {:ok,
         %{
           status_code: 204,
           body: "",
           headers: [{"opc-request-id", "req-del-1"}]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.delete_object(os_client, @namespace, @bucket, object_name)

      assert result.data == nil
      assert result.metadata[:opc_request_id] == "req-del-1"
    end

    test "sends versionId query param when version_id provided", %{os_client: os_client} do
      object_name = "versioned.txt"

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :delete
        assert Map.get(headers, "if-match") == "etag-v2"
        assert url =~ "versionId=v2"

        {:ok,
         %{
           status_code: 204,
           body: "",
           headers: [{"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.delete_object(
                 os_client,
                 @namespace,
                 @bucket,
                 object_name,
                 version_id: "v2",
                 if_match: "etag-v2"
               )
    end
  end

  describe "list_objects/4" do
    setup do
      client = build_client()

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn input, _opts ->
        assert input == ""
        ""
      end)

      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "lists objects with default options", %{os_client: os_client} do
      response_body = ~s({"objects": [{"name": "file.txt"}], "nextStartWith": null})

      response_parsed =
        %{
          "objects" => [%{"name" => "file.txt"}],
          "next_start_with" => nil
        }

      expect(ExOciSdk.JSONMock, :decode!, fn input, _opts ->
        assert input == response_body
        response_parsed
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, req_body, headers, _opts ->
        assert method == :get
        assert req_body == ""
        assert Map.get(headers, "content-type") == "application/json"
        assert url == "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o"

        {:ok,
         %{
           status_code: 200,
           body: response_body,
           headers: [
             {"content-type", "application/json"},
             {"opc-request-id", "req-list-1"}
           ]
         }}
      end)

      assert {:ok, result} = ObjectStorageClient.list_objects(os_client, @namespace, @bucket)
      assert result.data == response_parsed
      assert result.metadata[:opc_request_id] == "req-list-1"
    end

    test "sends query params when options provided", %{os_client: os_client} do
      expect(ExOciSdk.JSONMock, :decode!, fn _input, _opts -> %{"objects" => []} end)

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, url, _body, _headers, _opts ->
        assert url =~ "prefix=images%2F"
        assert url =~ "limit=50"
        assert url =~ "startAfter=img001.png"

        {:ok,
         %{
           status_code: 200,
           body: ~s({"objects":[]}),
           headers: [{"content-type", "application/json"}, {"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.list_objects(
                 os_client,
                 @namespace,
                 @bucket,
                 prefix: "images/",
                 limit: 50,
                 start_after: "img001.png"
               )
    end
  end

  describe "get_object_metadata/5" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "retrieves all object headers via HEAD request", %{os_client: os_client} do
      object_name = "documents/report.pdf"

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, req_body, headers, _opts ->
        assert method == :head
        assert req_body == ""
        assert Map.has_key?(headers, "authorization")

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/o/#{URI.encode(object_name)}"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [
             {"etag", "etag-doc"},
             {"content-length", "1024"},
             {"content-type", "application/pdf"},
             {"last-modified", "Tue, 01 Apr 2025 12:00:00 GMT"},
             {"opc-meta-author", "Alice"},
             {"storage-tier", "Standard"},
             {"opc-request-id", "req-head-1"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.get_object_metadata(
                 os_client,
                 @namespace,
                 @bucket,
                 object_name
               )

      assert result.data == nil
      assert result.metadata[:opc_request_id] == "req-head-1"
      assert result.metadata["etag"] == "etag-doc"
      assert result.metadata["content-length"] == "1024"
      assert result.metadata["opc-meta-author"] == "Alice"
      assert result.metadata["storage-tier"] == "Standard"
    end

    test "sends versionId and if-match headers when provided", %{os_client: os_client} do
      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :head
        assert Map.get(headers, "if-match") == "etag-v3"
        assert url =~ "versionId=v3"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [{"etag", "etag-v3"}, {"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.get_object_metadata(
                 os_client,
                 @namespace,
                 @bucket,
                 "report.pdf",
                 version_id: "v3",
                 if_match: "etag-v3"
               )
    end
  end

  describe "create_multipart_upload/5" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "initiates multipart upload and returns upload_id", %{os_client: os_client} do
      input = %{object: "large-file.bin", content_type: "application/octet-stream"}
      encoded_input = KeyConverter.snake_to_camel(input)

      response_body = ~s({"bucket":"my-bucket","object":"large-file.bin","uploadId":"uid-123"})

      response_parsed = %{
        "bucket" => "my-bucket",
        "object" => "large-file.bin",
        "upload_id" => "uid-123"
      }

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        response_body
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn input, _opts ->
        assert input == response_body
        response_parsed
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :post
        assert Map.get(headers, "content-type") == "application/json"
        assert url == "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/u"

        {:ok,
         %{
           status_code: 200,
           body: response_body,
           headers: [
             {"content-type", "application/json"},
             {"opc-request-id", "req-mpu-1"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.create_multipart_upload(os_client, @namespace, @bucket, input)

      assert result.data == response_parsed
      assert result.metadata[:opc_request_id] == "req-mpu-1"
    end

    test "sends if-none-match header when provided", %{os_client: os_client} do
      input = %{object: "new-file.bin"}
      encoded_input = KeyConverter.snake_to_camel(input)

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        ~s({"object":"new-file.bin","uploadId":"uid-999"})
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn _input, _opts ->
        %{"upload_id" => "uid-999"}
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, _url, _body, headers, _opts ->
        assert Map.get(headers, "if-none-match") == "*"

        {:ok,
         %{
           status_code: 200,
           body: ~s({"object":"new-file.bin","uploadId":"uid-999"}),
           headers: [{"content-type", "application/json"}, {"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.create_multipart_upload(
                 os_client,
                 @namespace,
                 @bucket,
                 input,
                 if_none_match: "*"
               )
    end
  end

  describe "commit_multipart_upload/7" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "commits multipart upload with parts list", %{os_client: os_client} do
      object_name = "large-file.bin"
      upload_id = "uid-abc"

      commit_input = %{
        parts_to_commit: [
          %{part_num: 1, etag: "etag-part-1"},
          %{part_num: 2, etag: "etag-part-2"}
        ]
      }

      encoded_input = KeyConverter.snake_to_camel(commit_input)

      response_body = ""

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        response_body
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :post
        assert Map.get(headers, "content-type") == "application/json"

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/u/#{object_name}?uploadId=#{upload_id}"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [
             {"etag", "etag-final"},
             {"last-modified", "Wed, 02 Jan 2026 00:00:00 GMT"},
             {"opc-multipart-md5", "md5-hash=="},
             {"opc-request-id", "req-commit-1"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.commit_multipart_upload(
                 os_client,
                 @namespace,
                 @bucket,
                 object_name,
                 upload_id,
                 commit_input
               )

      assert result.data == nil
      assert result.metadata["etag"] == "etag-final"
      assert result.metadata["opc-multipart-md5"] == "md5-hash=="
      assert result.metadata[:opc_request_id] == "req-commit-1"
    end

    test "sends if-match header when provided", %{os_client: os_client} do
      commit_input = %{parts_to_commit: [%{part_num: 1, etag: "etag-p1"}]}
      encoded_input = KeyConverter.snake_to_camel(commit_input)

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        ""
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, _url, _body, headers, _opts ->
        assert Map.get(headers, "if-match") == "etag-original"

        {:ok,
         %{
           status_code: 200,
           body: "",
           headers: [{"etag", "etag-final"}, {"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, _} =
               ObjectStorageClient.commit_multipart_upload(
                 os_client,
                 @namespace,
                 @bucket,
                 "large-file.bin",
                 "uid-abc",
                 commit_input,
                 if_match: "etag-original"
               )
    end
  end

  describe "create_preauthenticated_request/5" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "creates a PAR for object read access", %{os_client: os_client} do
      par_input = %{
        name: "my-par",
        access_type: "ObjectRead",
        time_expires: "2026-12-31T23:59:59Z",
        object_name: "report.pdf"
      }

      encoded_input = KeyConverter.snake_to_camel(par_input)

      response_body =
        ~s({"id":"par-id-1","name":"my-par","accessType":"ObjectRead","objectName":"report.pdf","uri":"/p/TOKEN/n/ns/b/bucket/o/report.pdf","timeExpires":"2026-12-31T23:59:59Z"})

      response_parsed = %{
        "id" => "par-id-1",
        "name" => "my-par",
        "access_type" => "ObjectRead",
        "object_name" => "report.pdf",
        "uri" => "/p/TOKEN/n/ns/b/bucket/o/report.pdf",
        "time_expires" => "2026-12-31T23:59:59Z"
      }

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        response_body
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn input, _opts ->
        assert input == response_body
        response_parsed
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :post
        assert Map.get(headers, "content-type") == "application/json"
        assert url == "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/p"

        {:ok,
         %{
           status_code: 200,
           body: response_body,
           headers: [
             {"content-type", "application/json"},
             {"opc-request-id", "req-par-1"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.create_preauthenticated_request(
                 os_client,
                 @namespace,
                 @bucket,
                 par_input
               )

      assert result.data == response_parsed
      assert result.data["uri"] == "/p/TOKEN/n/ns/b/bucket/o/report.pdf"
      assert result.metadata[:opc_request_id] == "req-par-1"
    end

    test "creates a PAR for any-object write access", %{os_client: os_client} do
      par_input = %{
        name: "bulk-upload-par",
        access_type: "AnyObjectWrite",
        time_expires: "2026-06-30T23:59:59Z"
      }

      encoded_input = KeyConverter.snake_to_camel(par_input)

      response_body = ~s({"id":"par-id-2","accessType":"AnyObjectWrite","uri":"/p/TOKEN2"})

      response_parsed = %{
        "id" => "par-id-2",
        "access_type" => "AnyObjectWrite",
        "uri" => "/p/TOKEN2"
      }

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        response_body
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn _input, _opts -> response_parsed end)

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, _url, _body, _headers, _opts ->
        {:ok,
         %{
           status_code: 200,
           body: response_body,
           headers: [{"content-type", "application/json"}, {"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.create_preauthenticated_request(
                 os_client,
                 @namespace,
                 @bucket,
                 par_input
               )

      assert result.data == response_parsed
    end
  end

  describe "batch_delete_objects/5" do
    setup do
      client = build_client()
      os_client = ObjectStorageClient.create(client)
      %{os_client: os_client}
    end

    test "batch deletes objects and returns deleted/failed arrays", %{os_client: os_client} do
      batch_input = %{
        objects: [
          %{object_name: "file1.txt"},
          %{object_name: "file2.txt", if_match: "etag-f2"}
        ]
      }

      encoded_input = KeyConverter.snake_to_camel(batch_input)

      response_body =
        ~s({"deleted":[{"objectName":"file1.txt"},{"objectName":"file2.txt"}],"failed":[]})

      response_parsed = %{
        "deleted" => [%{"object_name" => "file1.txt"}, %{"object_name" => "file2.txt"}],
        "failed" => []
      }

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        response_body
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn input, _opts ->
        assert input == response_body
        response_parsed
      end)

      expect(ExOciSdk.HTTPClientMock, :request, fn method, url, _body, headers, _opts ->
        assert method == :post
        assert Map.get(headers, "content-type") == "application/json"

        assert url ==
                 "#{@region_endpoint}/n/#{@namespace}/b/#{@bucket}/actions/batchDeleteObjects"

        {:ok,
         %{
           status_code: 200,
           body: response_body,
           headers: [
             {"content-type", "application/json"},
             {"opc-request-id", "req-batch-1"}
           ]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.batch_delete_objects(
                 os_client,
                 @namespace,
                 @bucket,
                 batch_input
               )

      assert result.data == response_parsed
      assert length(result.data["deleted"]) == 2
      assert result.data["failed"] == []
      assert result.metadata[:opc_request_id] == "req-batch-1"
    end

    test "sends is_skip_deleted_result flag in body", %{os_client: os_client} do
      batch_input = %{
        objects: [%{object_name: "already-gone.txt"}],
        is_skip_deleted_result: true
      }

      encoded_input = KeyConverter.snake_to_camel(batch_input)

      response_body = ~s({"deleted":[],"failed":[]})
      response_parsed = %{"deleted" => [], "failed" => []}

      expect(ExOciSdk.JSONMock, :encode_to_iodata!, fn body_input, _opts ->
        assert body_input == encoded_input
        assert body_input["isSkipDeletedResult"] == true
        response_body
      end)

      expect(ExOciSdk.JSONMock, :decode!, fn _input, _opts -> response_parsed end)

      expect(ExOciSdk.HTTPClientMock, :request, fn _method, _url, _body, _headers, _opts ->
        {:ok,
         %{
           status_code: 200,
           body: response_body,
           headers: [{"content-type", "application/json"}, {"opc-request-id", "r"}]
         }}
      end)

      assert {:ok, result} =
               ObjectStorageClient.batch_delete_objects(
                 os_client,
                 @namespace,
                 @bucket,
                 batch_input
               )

      assert result.data["deleted"] == []
    end
  end
end
