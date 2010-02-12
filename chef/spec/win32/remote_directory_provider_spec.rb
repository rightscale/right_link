# Copyright (c) 2010 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

  require 'fileutils'
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module RemoteDirectoryProviderSpec
    TEST_TEMP_PATH = File.expand_path(File.join(Dir.tmpdir, "remote-file-provider-spec-7C75ED9D-E143-4092-9472-0A8598192B59")).gsub("\\", "/")
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
    TEST_COOKBOOK_PATH = File.join(TEST_COOKBOOKS_PATH, 'test')
    SOURCE_DIR_PATH = File.join(TEST_COOKBOOK_PATH, 'files', 'default', 'test_dir')
    SOURCE_FILE_PATH = File.join(SOURCE_DIR_PATH, 'test.txt')
    TEST_DIR_PATH = File.join(TEST_TEMP_PATH, 'data', 'test_dir')
    TEST_FILE_PATH = File.join(TEST_DIR_PATH, 'test.txt')

    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
        TEST_TEMP_PATH,
        {
          :create_remote_directory_recipe => (
<<EOF
remote_directory "#{TEST_DIR_PATH}" do
  source "#{File.basename(SOURCE_DIR_PATH)}"
  mode 0440
end
EOF
          )
        }
      )

      # template source.
      FileUtils.mkdir_p(File.dirname(SOURCE_FILE_PATH))
      source_text =
<<EOF
Remote directory test
EOF
      File.open(SOURCE_FILE_PATH, "w") { |f| f.write(source_text) }
    end

    module_function :create_cookbook

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :cleanup
  end

  describe Chef::Provider::RemoteDirectory do

    before(:all) do
      @old_logger = Chef::Log.logger
      RemoteDirectoryProviderSpec.create_cookbook
      FileUtils.mkdir_p(File.dirname(RemoteDirectoryProviderSpec::TEST_DIR_PATH))
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      RemoteDirectoryProviderSpec.cleanup
    end

    it "should create remote directories on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          RemoteDirectoryProviderSpec::TEST_COOKBOOKS_PATH,
          'test::create_remote_directory_recipe') }
      runner.call.should == true
      File.directory?(RemoteDirectoryProviderSpec::TEST_DIR_PATH).should == true
      File.file?(RemoteDirectoryProviderSpec::TEST_FILE_PATH).should == true
      message = File.read(RemoteDirectoryProviderSpec::TEST_FILE_PATH)
      message.chomp.should == "Remote directory test"
      File.delete(RemoteDirectoryProviderSpec::TEST_FILE_PATH)
    end

  end

end # if windows?
