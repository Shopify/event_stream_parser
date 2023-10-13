# encoding: utf-8
# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "event_stream_parser/version"

Gem::Specification.new do |spec|
  spec.name          = "event_stream_parser"
  spec.version       = EventStreamParser::VERSION
  spec.platform      = Gem::Platform::RUBY
  spec.authors       = ["Ates Goral"]
  spec.email         = ["ates.goral@shopify.com"]

  spec.summary       = "A spec-compliant event stream parser"
  spec.homepage      = "https://github.com/Shopify/event_stream_parser"
  spec.license       = "MIT"

  spec.required_ruby_version     = ">= 2.7.0"
  spec.required_rubygems_version = ">= 1.3.7"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.files = Dir.glob("{lib}/**/*") + ["LICENSE.md", "README.md"]

  spec.extra_rdoc_files = ["README.md"]

  spec.require_paths = ["lib"]

  spec.add_development_dependency("bundler", "~> 1.17")
  spec.add_development_dependency("minitest", "~> 5.0")
  spec.add_development_dependency("rake", "~> 13.0")
end
