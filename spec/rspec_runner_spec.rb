require 'gorgon/rspec_runner'

describe RspecRunner do

  subject {RspecRunner}
  it {should respond_to(:run_file).with(1).argument}
  it {should respond_to(:runner).with(0).argument}

  describe "#run_file" do
    let(:configuration) { double('Configuration', include_or_extend_modules: ['modules'],
                                 :include_or_extend_modules= => nil) }

    before do
      RSpec::Core::Runner.stub(:run)
      RSpec.stub(configuration: configuration)
    end

    it "uses Rspec runner to run filename and uses the correct options" do
      RSpec::Core::Runner.should_receive(:run).with(["-f",
                                                     "RSpec::Core::Formatters::GorgonRspecFormatter",
                                                     "file"], anything, anything)
      RspecRunner.run_file "file"
    end

    it "passes StringIO's (or something similar) to rspec runner" do
      RSpec::Core::Runner.should_receive(:run).with(anything,
                                                    duck_type(:read, :write, :close),
                                                    duck_type(:read, :write, :close))
      RspecRunner.run_file "file"
    end

    it "parses the output of the Runner and returns it" do
      str_io = stub("StringIO", :rewind => nil, :read => :content)
      StringIO.stub!(:new).and_return(str_io)
      Yajl::Parser.any_instance.should_receive(:parse).with(:content).and_return :result
      RspecRunner.run_file("file").should == :result
    end

    # since configuration is reset on each run
    # https://github.com/rspec/rspec-core/issues/621
    it 'restore initial rspec configuration' do
      RSpec.configuration.should_receive(:include_or_extend_modules=).with(['modules'])
      RspecRunner.run_file "file"
    end
  end

  describe "#runner" do
    it "returns :rspec" do
      RspecRunner.runner.should == :rspec
    end
  end
end
