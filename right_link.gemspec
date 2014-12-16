# -*- mode: ruby; encoding: utf-8 -*-

spec = Gem::Specification.new do |s|
  s.name        = 'right_link'
  s.version     = '6.3.0'
  s.platform    = Gem::Platform::RUBY

  s.authors     = ['RightScale']
  s.email       = 'support@rightscale.com'
  s.homepage    = 'https://github.com/rightscale/right_link'

  s.summary     = %q{RightScale management agent.}
  s.description = %q{A daemon that connects systems to the RightScale cloud management platform.}

  s.required_rubygems_version = '>= 1.3.7'

  s.add_runtime_dependency('right_agent', '~> 2.0')
  s.add_runtime_dependency('right_popen', '~> 2.0')
  s.add_runtime_dependency('right_git')
  s.add_runtime_dependency('right_scraper', '~> 4.0')
  s.add_runtime_dependency('right_http_connection', '~> 1.3')
  s.add_runtime_dependency('right_support', '~> 2.0')
  s.add_runtime_dependency('net-dhcp',      '~> 1.3')

  s.add_runtime_dependency('chef', '>= 0.10.10')
  s.add_runtime_dependency('encryptor', '~> 1.1')
  s.add_runtime_dependency('trollop')
  s.add_runtime_dependency('extlib', '~> 0.9.15')

  if s.platform.to_s =~ /mswin|mingw/
    s.add_runtime_dependency('win32-dir')
    s.add_runtime_dependency('win32-process')
    s.add_runtime_dependency('win32-pipe')
  end

  s.files = ['RELEASES.rdoc', 'INSTALL.rdoc', 'LICENSE', 'README.rdoc'] +
            Dir.glob('init/*') +
            Dir.glob('actors/*.rb') +
            Dir.glob('bin/*') +
            Dir.glob('ext/Rakefile') +
            Dir.glob('lib/chef/windows/**/*.cs') +
            Dir.glob('lib/chef/windows/**/*.csproj') +
            Dir.glob('lib/chef/windows/bin/*.dll') +
            Dir.glob('lib/chef/windows/**/*.ps1') +
            Dir.glob('lib/chef/windows/**/*.sln') +
            Dir.glob('lib/chef/windows/**/*.txt') +
            Dir.glob('lib/chef/windows/**/*.xml') +
            Dir.glob('lib/chef/ohai/**/*.ps1') +
            Dir.glob('lib/**/*.pub') +
            Dir.glob('lib/**/*.rb') +
            Dir.glob('scripts/*') +
            Dir.glob('lib/instance/cook/*.crt')

  # eliminate any files generated by calling rake build under Windows.
  s.files.delete_if do |filepath|
    filepath.index('/Release/') || filepath.index('/Debug/')
  end

  s.executables = Dir.glob('bin/*').map { |f| File.basename(f) }
  s.extensions = ["ext/Rakefile"]
end
