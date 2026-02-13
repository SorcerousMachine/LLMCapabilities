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
end
