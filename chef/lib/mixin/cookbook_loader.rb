#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2010 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'chef/cookbook_loader'

class String
  unless method_defined?(:starts_with?)
    def starts_with?(prefix)
      prefix = prefix.to_s
      self[0, prefix.length] == prefix
    end
  end
end

class Chef
  # monkey patch unbelievably broken cookbook loader
  class CookbookLoader
    def load_cascading_files(file_glob, base_path, result_hash)
      start = base_path.size
      # To handle dotfiles like .ssh
      Dir.glob(File.join(base_path, "**/#{file_glob}"), File::FNM_DOTMATCH).each do |file|
        raise "Eh?  Filename #{file} doesn't start with #{base_path}?!" unless
          file.starts_with?(base_path)
        result_hash[file[start+1..-1]] = file
      end
    end
  end
end