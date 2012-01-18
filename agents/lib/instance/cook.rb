#
# Copyright (c) 2009 RightScale Inc
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

# Load files required by then runner process
# This process is responsible for running Chef
# It's a short lived process that runs one Chef converge then dies
# It talks back to the RightLink agent using the command protocol

require File.normalize_path(File.join(File.dirname(__FILE__), 'cook', 'audit_stub.rb'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'cook', 'cook_state.rb'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'cook', 'chef_state'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'cook', 'executable_sequence.rb'))