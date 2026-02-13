# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe LLMCapabilities::ModelIndex do
  let(:index_dir) { Dir.mktmpdir }
  let(:index_path) { File.join(index_dir, "model_index.json") }
  subject(:model_index) { described_class.new(path: index_path, ttl: 86_400) }

  let(:openrouter_response) do
    {
      "data" => [
        {
          "id" => "openai/o4-mini",
          "supported_parameters" => %w[structured_outputs tools reasoning temperature],
          "architecture" => {
            "input_modalities" => %w[text image],
            "output_modalities" => %w[text]
          }
        },
        {
          "id" => "anthropic/claude-sonnet-4.5",
          "supported_parameters" => %w[tools temperature response_format],
          "architecture" => {
            "input_modalities" => %w[text image],
            "output_modalities" => %w[text]
          }
        },
        {
          "id" => "qwen/qwen3-235b",
          "supported_parameters" => %w[temperature],
          "architecture" => {
            "input_modalities" => %w[text],
            "output_modalities" => %w[text]
          }
        }
      ]
    }
  end

  after do
    FileUtils.rm_rf(index_dir)
    WebMock.reset!
  end

  describe "#lookup from cached index file" do
    before do
      # Pre-populate index file
      normalized = {
        "openai/o4-mini" => {"structured_output" => true, "function_calling" => true, "reasoning" => true, "vision" => true},
        "anthropic/claude-sonnet-4.5" => {"function_calling" => true, "json_mode" => true, "vision" => true}
      }
      File.write(index_path, JSON.pretty_generate(normalized))
    end

    it "returns true for a supported capability" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be true
    end

    it "returns true for vision capability" do
      expect(model_index.lookup("openai/o4-mini", :vision)).to be true
    end

    it "returns nil for unknown model" do
      expect(model_index.lookup("unknown/model", :structured_output)).to be_nil
    end

    it "returns nil for unknown capability on known model" do
      expect(model_index.lookup("openai/o4-mini", :streaming)).to be_nil
    end
  end

  describe "fetches from OpenRouter when index missing" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "fetches and returns capability" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be true
    end

    it "caches index to disk" do
      model_index.lookup("openai/o4-mini", :structured_output)
      expect(File.exist?(index_path)).to be true
    end

    it "does not refetch on second lookup" do
      model_index.lookup("openai/o4-mini", :structured_output)
      model_index.lookup("openai/o4-mini", :vision)

      expect(WebMock).to have_requested(:get, "https://openrouter.ai/api/v1/models").once
    end
  end

  describe "fetches from OpenRouter when index stale" do
    before do
      # Write a stale index file
      File.write(index_path, JSON.pretty_generate({"old/model" => {"vision" => true}}))
      # Backdate file to exceed TTL
      FileUtils.touch(index_path, mtime: Time.now - 86_401)

      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "refetches when stale" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be true
      expect(WebMock).to have_requested(:get, "https://openrouter.ai/api/v1/models").once
    end
  end

  describe "respects TTL" do
    before do
      # Write a fresh index file
      normalized = {
        "openai/o4-mini" => {"structured_output" => true}
      }
      File.write(index_path, JSON.pretty_generate(normalized))

      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "does not refetch when fresh" do
      model_index.lookup("openai/o4-mini", :structured_output)
      expect(WebMock).not_to have_requested(:get, "https://openrouter.ai/api/v1/models")
    end
  end

  describe "survives network errors" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_raise(Errno::ECONNREFUSED)
    end

    it "returns nil on network error" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end
  end

  describe "survives HTTP errors" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 500, body: "Internal Server Error")
    end

    it "returns nil on 500" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end
  end

  describe "normalizes OpenRouter response correctly" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "maps structured_outputs to structured_output" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be true
    end

    it "maps tools to function_calling" do
      expect(model_index.lookup("openai/o4-mini", :function_calling)).to be true
    end

    it "maps reasoning" do
      expect(model_index.lookup("openai/o4-mini", :reasoning)).to be true
    end

    it "maps response_format to json_mode" do
      expect(model_index.lookup("anthropic/claude-sonnet-4.5", :json_mode)).to be true
    end

    it "maps image input_modality to vision" do
      expect(model_index.lookup("openai/o4-mini", :vision)).to be true
    end

    it "does not map capabilities for models without them" do
      expect(model_index.lookup("qwen/qwen3-235b", :structured_output)).to be_nil
    end
  end

  describe "handles corrupt index file" do
    before do
      File.write(index_path, "not valid json {{{")

      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "refetches on corrupt file" do
      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be true
      expect(WebMock).to have_requested(:get, "https://openrouter.ai/api/v1/models").once
    end
  end

  describe "normalize edge cases" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
    end

    it "returns empty hash when data key is missing" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({"other" => "stuff"}))

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "returns empty hash when data is null" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({"data" => nil}))

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "skips non-Hash model entries" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({"data" => ["not_a_hash", 42]}))

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "skips model entries missing id" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({
          "data" => [{"supported_parameters" => %w[tools]}]
        }))

      expect(model_index.lookup("openai/o4-mini", :function_calling)).to be_nil
    end

    it "skips model entries where id is integer" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({
          "data" => [{"id" => 123, "supported_parameters" => %w[tools]}]
        }))

      expect(model_index.lookup("123", :function_calling)).to be_nil
    end
  end

  describe "map_capabilities edge cases" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
    end

    it "ignores non-array supported_parameters" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({
          "data" => [{
            "id" => "test/model",
            "supported_parameters" => "not_an_array",
            "architecture" => {
              "input_modalities" => %w[text image],
              "output_modalities" => %w[text]
            }
          }]
        }))

      # No parameter-based capabilities mapped, but vision still detected from architecture
      expect(model_index.lookup("test/model", :structured_output)).to be_nil
      expect(model_index.lookup("test/model", :function_calling)).to be_nil
      expect(model_index.lookup("test/model", :vision)).to be true
    end

    it "produces no vision/image_generation when architecture is null" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({
          "data" => [{
            "id" => "test/model",
            "supported_parameters" => %w[tools],
            "architecture" => nil
          }]
        }))

      expect(model_index.lookup("test/model", :vision)).to be_nil
      expect(model_index.lookup("test/model", :image_generation)).to be_nil
      expect(model_index.lookup("test/model", :function_calling)).to be true
    end

    it "sets both vision and image_generation when image in both modalities" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate({
          "data" => [{
            "id" => "test/multimodal",
            "supported_parameters" => [],
            "architecture" => {
              "input_modalities" => %w[text image],
              "output_modalities" => %w[text image]
            }
          }]
        }))

      expect(model_index.lookup("test/multimodal", :vision)).to be true
      expect(model_index.lookup("test/multimodal", :image_generation)).to be true
    end
  end

  describe "HTTP error edge cases" do
    it "returns nil on 404" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 404, body: "Not Found")

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "returns nil on 200 with empty body" do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: "")

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "returns nil on 200 with nil body" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(nil)
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
    end
  end

  describe "deserialization filtering" do
    it "drops non-boolean values" do
      data = {
        "test/model" => {
          "vision" => true,
          "streaming" => "yes",
          "count" => 42,
          "nothing" => nil,
          "function_calling" => false
        }
      }
      File.write(index_path, JSON.pretty_generate(data))

      expect(model_index.lookup("test/model", :vision)).to be true
      expect(model_index.lookup("test/model", :function_calling)).to be false
      expect(model_index.lookup("test/model", :streaming)).to be_nil
    end

    it "skips non-Hash capability values during deserialization" do
      data = {
        "test/model" => "not_a_hash",
        "good/model" => {"vision" => true}
      }
      File.write(index_path, JSON.pretty_generate(data))

      expect(model_index.lookup("test/model", :vision)).to be_nil
      expect(model_index.lookup("good/model", :vision)).to be true
    end
  end

  describe "serialization/deserialization roundtrip" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "preserves symbol keys through serialize -> deserialize" do
      model_index.lookup("openai/o4-mini", :structured_output)

      fresh_index = described_class.new(path: index_path, ttl: 86_400)
      expect(fresh_index.lookup("openai/o4-mini", :structured_output)).to be true
      expect(fresh_index.lookup("openai/o4-mini", :vision)).to be true
    end
  end

  describe "TTL boundary" do
    it "refetches when exactly stale (elapsed == TTL + 1 second)" do
      normalized = {"openai/o4-mini" => {"structured_output" => true}}
      File.write(index_path, JSON.pretty_generate(normalized))
      FileUtils.touch(index_path, mtime: Time.now - 86_401)

      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))

      model_index.lookup("openai/o4-mini", :structured_output)
      expect(WebMock).to have_requested(:get, "https://openrouter.ai/api/v1/models").once
    end
  end

  describe "empty JSON object on disk" do
    it "returns empty index without fetching" do
      File.write(index_path, JSON.pretty_generate({}))

      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))

      expect(model_index.lookup("openai/o4-mini", :structured_output)).to be_nil
      expect(WebMock).not_to have_requested(:get, "https://openrouter.ai/api/v1/models")
    end
  end

  describe "persist! creates directory" do
    it "creates nested directory when it does not exist" do
      nested_path = File.join(index_dir, "nested", "deep", "index.json")
      nested_index = described_class.new(path: nested_path, ttl: 86_400)

      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))

      expect(nested_index.lookup("openai/o4-mini", :structured_output)).to be true
      expect(File.exist?(nested_path)).to be true
    end
  end

  describe "in-memory index reuse" do
    before do
      stub_request(:get, "https://openrouter.ai/api/v1/models")
        .to_return(status: 200, body: JSON.generate(openrouter_response))
    end

    it "does not re-enter load_index! on second lookup" do
      model_index.lookup("openai/o4-mini", :structured_output)

      # Delete the file to prove second lookup uses in-memory cache
      File.delete(index_path)

      expect(model_index.lookup("openai/o4-mini", :vision)).to be true
      expect(WebMock).to have_requested(:get, "https://openrouter.ai/api/v1/models").once
    end
  end
end
