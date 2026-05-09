# frozen_string_literal: true

require_relative "lib/archaeo/version"

Gem::Specification.new do |spec|
  spec.name = "archaeo"
  spec.version = Archaeo::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Ruby client for the Internet Archive Wayback Machine APIs"
  spec.description = "Archaeo provides a Ruby interface to query, fetch, " \
                     "and save archived web content via the Wayback Machine " \
                     "CDX Server API, Availability API, SavePageNow API, " \
                     "and content fetching."
  spec.homepage = "https://github.com/riboseinc/archaeo"
  spec.required_ruby_version = ">= 3.0.0"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] =
    "#{spec.homepage}/blob/main/CHANGELOG.adoc"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__,
                                             err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      f == __FILE__ ||
        f.start_with?(*%w[Gemfile .gitignore .rspec spec/ .github/
                          .rubocop TODO])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "nokogiri", "~> 1.14"
  spec.add_dependency "thor", "~> 1.3"
end
