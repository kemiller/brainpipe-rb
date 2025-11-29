require "webmock/rspec"
require "base64"

RSpec.describe Brainpipe::Image do
  let(:test_image_data) { "\x89PNG\r\n\x1a\n" + ("x" * 100) }
  let(:encoded_data) { Base64.strict_encode64(test_image_data) }

  describe ".from_file" do
    let(:tmpfile) { File.join(Dir.tmpdir, "test_image.png") }

    before do
      File.binwrite(tmpfile, test_image_data)
    end

    after do
      File.delete(tmpfile) if File.exist?(tmpfile)
    end

    it "loads image data from file" do
      image = described_class.from_file(tmpfile)
      expect(image.base64).to eq(encoded_data)
    end

    it "infers MIME type from extension" do
      image = described_class.from_file(tmpfile)
      expect(image.mime_type).to eq("image/png")
    end

    it "handles jpeg extension" do
      jpeg_file = File.join(Dir.tmpdir, "test_image.jpg")
      File.binwrite(jpeg_file, test_image_data)

      image = described_class.from_file(jpeg_file)
      expect(image.mime_type).to eq("image/jpeg")
    ensure
      File.delete(jpeg_file) if File.exist?(jpeg_file)
    end

    it "handles webp extension" do
      webp_file = File.join(Dir.tmpdir, "test_image.webp")
      File.binwrite(webp_file, test_image_data)

      image = described_class.from_file(webp_file)
      expect(image.mime_type).to eq("image/webp")
    ensure
      File.delete(webp_file) if File.exist?(webp_file)
    end

    it "raises error for non-existent file" do
      expect { described_class.from_file("/nonexistent/path.png") }
        .to raise_error(ArgumentError, /File not found/)
    end

    it "raises error for unknown extension" do
      unknown_file = File.join(Dir.tmpdir, "test_image.xyz")
      File.binwrite(unknown_file, test_image_data)

      expect { described_class.from_file(unknown_file) }
        .to raise_error(ArgumentError, /Could not determine MIME type/)
    ensure
      File.delete(unknown_file) if File.exist?(unknown_file)
    end
  end

  describe ".from_url" do
    let(:url) { "https://example.com/image.png" }

    it "stores URL without fetching" do
      image = described_class.from_url(url)
      expect(image.url?).to be true
      expect(image.url).to eq(url)
    end

    it "infers MIME type from URL path" do
      image = described_class.from_url(url)
      expect(image.mime_type).to eq("image/png")
    end

    it "allows explicit MIME type override" do
      image = described_class.from_url(url, mime_type: "image/jpeg")
      expect(image.mime_type).to eq("image/jpeg")
    end

    it "fetches base64 lazily when requested" do
      stub_request(:get, url).to_return(body: test_image_data, status: 200)

      image = described_class.from_url(url)
      expect(a_request(:get, url)).not_to have_been_made

      base64 = image.base64
      expect(a_request(:get, url)).to have_been_made.once
      expect(base64).to eq(encoded_data)
    end

    it "caches fetched base64 data" do
      stub_request(:get, url).to_return(body: test_image_data, status: 200)

      image = described_class.from_url(url)
      image.base64
      image.base64

      expect(a_request(:get, url)).to have_been_made.once
    end

    it "follows redirects" do
      redirect_url = "https://cdn.example.com/image.png"
      stub_request(:get, url).to_return(status: 302, headers: { "Location" => redirect_url })
      stub_request(:get, redirect_url).to_return(body: test_image_data, status: 200)

      image = described_class.from_url(url)
      expect(image.base64).to eq(encoded_data)
    end

    it "raises error on fetch failure" do
      stub_request(:get, url).to_return(status: 404)

      image = described_class.from_url(url)
      expect { image.base64 }.to raise_error(Brainpipe::ExecutionError, /Failed to fetch image/)
    end
  end

  describe ".from_base64" do
    it "stores base64 data with MIME type" do
      image = described_class.from_base64(encoded_data, mime_type: "image/png")
      expect(image.base64?).to be true
      expect(image.base64).to eq(encoded_data)
      expect(image.mime_type).to eq("image/png")
    end

    it "requires MIME type" do
      expect { described_class.from_base64(encoded_data, mime_type: nil) }
        .to raise_error(ArgumentError, /mime_type is required/)
    end
  end

  describe "#url?" do
    it "returns true for URL-based images" do
      image = described_class.from_url("https://example.com/image.png")
      expect(image.url?).to be true
    end

    it "returns false for base64-based images" do
      image = described_class.from_base64(encoded_data, mime_type: "image/png")
      expect(image.url?).to be false
    end
  end

  describe "#base64?" do
    it "returns false for URL-based images" do
      image = described_class.from_url("https://example.com/image.png")
      expect(image.base64?).to be false
    end

    it "returns true for base64-based images" do
      image = described_class.from_base64(encoded_data, mime_type: "image/png")
      expect(image.base64?).to be true
    end
  end

  describe "#url" do
    it "returns URL for URL-based images" do
      image = described_class.from_url("https://example.com/image.png")
      expect(image.url).to eq("https://example.com/image.png")
    end

    it "raises error for base64-based images" do
      image = described_class.from_base64(encoded_data, mime_type: "image/png")
      expect { image.url }.to raise_error(ArgumentError, /has no URL/)
    end
  end

  describe "immutability" do
    it "freezes the instance after construction" do
      image = described_class.from_url("https://example.com/image.png")
      expect(image).to be_frozen
    end

    it "freezes base64-based instances" do
      image = described_class.from_base64(encoded_data, mime_type: "image/png")
      expect(image).to be_frozen
    end

    it "freezes file-based instances" do
      tmpfile = File.join(Dir.tmpdir, "test_image.png")
      File.binwrite(tmpfile, test_image_data)

      image = described_class.from_file(tmpfile)
      expect(image).to be_frozen
    ensure
      File.delete(tmpfile) if File.exist?(tmpfile)
    end
  end

  describe "#initialize" do
    it "requires either url or base64" do
      expect { described_class.new }
        .to raise_error(ArgumentError, /Must provide either url or base64/)
    end

    it "rejects both url and base64" do
      expect { described_class.new(url: "https://example.com/image.png", base64: encoded_data) }
        .to raise_error(ArgumentError, /Cannot provide both url and base64/)
    end
  end

  describe "#inspect" do
    it "shows URL for URL-based images" do
      image = described_class.from_url("https://example.com/image.png")
      expect(image.inspect).to include("url=")
      expect(image.inspect).to include("example.com")
    end

    it "shows byte count for base64-based images" do
      image = described_class.from_base64(encoded_data, mime_type: "image/png")
      expect(image.inspect).to include("base64=")
      expect(image.inspect).to include("bytes")
    end
  end

  describe ".infer_mime_type_from_path" do
    {
      "image.jpg" => "image/jpeg",
      "image.jpeg" => "image/jpeg",
      "image.png" => "image/png",
      "image.gif" => "image/gif",
      "image.webp" => "image/webp",
      "image.bmp" => "image/bmp",
      "image.svg" => "image/svg+xml",
      "IMAGE.PNG" => "image/png"
    }.each do |filename, expected_mime|
      it "returns #{expected_mime} for #{filename}" do
        expect(described_class.infer_mime_type_from_path(filename)).to eq(expected_mime)
      end
    end

    it "returns nil for unknown extensions" do
      expect(described_class.infer_mime_type_from_path("image.xyz")).to be_nil
    end
  end
end
