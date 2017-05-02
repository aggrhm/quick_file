# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "quick_file/version"

Gem::Specification.new do |s|
  s.name        = "quick_file"
  s.version     = QuickFile::VERSION
  s.authors     = ["Alan Graham"]
  s.email       = ["alangraham5@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{A file upload library}
  s.description = %q{A file upload library for use with MongoDB and S3}

  s.rubyforge_project = "quick_file"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

	s.add_dependency 'rmagick'
	s.add_dependency 'mime-types'
	s.add_dependency 'aws-sdk', '2.2.5'
  s.add_dependency 'stacktor'
  s.add_dependency 'activesupport'

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
