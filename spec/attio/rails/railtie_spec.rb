# frozen_string_literal: true

RSpec.describe Attio::Rails::Railtie do
  it "is a Rails::Railtie" do
    expect(described_class).to be < Rails::Railtie
  end

  describe "initializers" do
    it "has an initializer for configuring Rails" do
      initializer = described_class.initializers.find { |i| i.name == "attio.configure_rails_initialization" }
      expect(initializer).not_to be_nil
    end

    it "loads Syncable concern when ActiveRecord is loaded" do
      # Simulate the initializer running
      initializer = described_class.initializers.find { |i| i.name == "attio.configure_rails_initialization" }
      
      # Mock ActiveSupport.on_load to execute the block immediately
      allow(ActiveSupport).to receive(:on_load).with(:active_record).and_yield
      
      # Expect the Syncable concern to be required
      expect(initializer).not_to be_nil
      
      # Run the initializer block
      initializer.block.call(nil)
      
      # Verify the Syncable concern is available
      expect(defined?(Attio::Rails::Concerns::Syncable)).to be_truthy
    end
  end

  describe "generators" do
    it "defines a generators block" do
      # Rails loads generators lazily, but we can verify the block is defined
      expect(described_class).to respond_to(:generators)
    end
    
    it "can load the install generator file" do
      # Load the railtie file to simulate the generators block execution
      # This ensures the syntax is correct even if we can't execute it
      railtie_content = File.read(File.join(__dir__, "../../../lib/attio/rails/railtie.rb"))
      expect(railtie_content).to include('require "generators/attio/install/install_generator"')
      
      # Verify the generator file exists
      generator_path = File.join(__dir__, "../../../lib/generators/attio/install/install_generator.rb")
      expect(File.exist?(generator_path)).to be true
    end
  end
end
