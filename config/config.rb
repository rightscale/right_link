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

# Instance agent configuration
# Configuration values are listed with the format:
# name value

# Current RightLink protocol version (no support below version 5)
# 5:  Started storing timestamps in database for each instance state rather than storing state name
#     Changed format of agent identifiers by replacing '-' with '*' as separator
# 6:  Attributes in RecipeInstantiation no longer converted to JSON format
#     (image 5.1.0)
# 7:  ???
# 8:  Deprecated full vs. partial converge distinction in ExecutableBundle
#     Core agent booter actor superseded :set_r_s_version action with :declare
#     Added request retry and duplicate request checking
#     (image 5.4.0)
# 9:  Introduced multiple brokers, which extended protocol but did not introduce any
#     downrev incompatibilities, but wanted clear demarcation if needed to resolve issues
#     (sprint 20, image 5.5.0)
# 10: Changed multicast requests to no longer be collected in mapper
#     Added request_from field to Result so that any mapper can forward a result to the original requester
#     Changed /mapper/list_agents to /mapper/query_tags
#     Eliminated agent periodic pings
#     Eliminated instance agent registration
#     Eliminated least_loaded and rr request selectors
#     Eliminated nanite and mapper prefix for queue names and pid files
#     Added returns field to Request, Push, and Result for message returns
#     (sprint 21, image 5.6.0)
# 11: Added stats packet, stats exchange & corresponding agent_manager request
#     Changed InstanceSetup to use the Repose mirror to download cookbook repositories
protocol_version 11

# Path to RightLink root folder
right_link_path File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'right_link'))

# Root path to RightScale files
# 
# note that use of parent of right_link_path makes rs_root_path normalized while
# the leaf of right_link_path remains "right_link" (i.e. long name instead of
# short name) under Windows.
rs_root_path File.dirname(right_link_path)

# Path to directory containing the certificates used to sign and encrypt all
# outgoing messages as well as to check the signature and decrypt any incoming
# messages.
# This directory should contain at least:
#  - The instance agent private key ('instance.key')
#  - The instance agent public certificate ('instance.cert')
#  - The mapper public certificate ('mapper.cert')
certs_dir File.join(rs_root_path, 'certs')

# Path to directory containing persistent RightLink agent state.
agent_state_dir platform.filesystem.right_scale_state_dir

# Path to directory containing transient cloud-related state (metadata, userdata, etc).
cloud_state_dir File.join(platform.filesystem.spool_dir, 'cloud')

# This logic is duplicated in right_link_install_gems.rb which cannot use
# this file due to chicken-and-egg problems with mixlib-config. If you change it
# here, please change it there and vice-versa.
if platform.windows?
  # note that we cannot use the provided windows gem.bat because it pulls any
  # ruby.exe on the PATH instead of using the companion ruby.exe from the same
  # bin directory.
  candidate_path = platform.filesystem.sandbox_dir
  if File.directory?(candidate_path)
    sandbox_path candidate_path
    
    # allow the automated test environment to specify a non-program files
    # location for tools.
    if ENV['RS_RUBY_EXE'] && ENV['RS_GEM']
      sandbox_ruby_cmd ENV['RS_RUBY_EXE']
      sandbox_gem_cmd ENV['RS_GEM']
    else
      sandbox_ruby_cmd platform.shell.sandbox_ruby
      sandbox_gem_cmd  "\"#{sandbox_ruby_cmd}\" \"#{File.join(sandbox_path, 'Ruby', 'bin', 'gem.exe')}\""
    end
    if ENV['RS_GIT_EXE']
      sandbox_git_cmd ENV['RS_GIT_EXE']
    else
      sandbox_git_cmd File.join(sandbox_path, 'bin', 'windows', 'git.cmd')
    end
  else
    # Development setup
    sandbox_path nil
    sandbox_ruby_cmd 'ruby'
    sandbox_gem_cmd  'gem'
    sandbox_git_cmd  'git'
  end
else
  candidate_path = platform.filesystem.sandbox_dir
  if File.directory?(candidate_path)
    sandbox_path candidate_path
    sandbox_ruby_cmd platform.shell.sandbox_ruby
    sandbox_gem_cmd  File.join(sandbox_path, 'bin', 'gem')
    sandbox_git_cmd  File.join(sandbox_path, 'bin', 'git')
  else
    # Development setup
    sandbox_path nil
    sandbox_ruby_cmd `which ruby`.chomp
    sandbox_gem_cmd  `which gem`.chomp
    sandbox_git_cmd  `which git`.chomp
  end
end