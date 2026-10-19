# frozen_string_literal: true

RSpec.describe XeroKiwi::Identity do
  describe ".build_http" do
    it "sets the timeouts it is given" do
      http = described_class.build_http(open_timeout: 1, timeout: 2, write_timeout: 3)

      expect(http.options).to have_attributes(open_timeout: 1, timeout: 2, write_timeout: 3)
    end

    it "waits 5 seconds to connect and 10 to read or write when no timeouts are given" do
      expect(described_class.build_http.options).to have_attributes(open_timeout: 5, timeout: 10, write_timeout: 10)
    end
  end
end
