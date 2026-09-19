# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# Boots the dummy application in a process of its own, with the environment a container would pass,
# and answers what telemetry made of it. Every switch is read once at boot and a process can only be
# one thing, so a boot is the only way to test what a variable does.
module Probe
  GEM = File.expand_path("../..", __dir__)

  def boot(as: nil, **variables)
    Dir.mktmpdir do |directory|
      report = File.join(directory, "report.json")
      environment = {
        "RAILS_ENV" => "test",
        "DUMMY_DATABASE" => File.join(directory, "queue.sqlite3"),
        "DUMMY_REPORT" => report
      }.merge(variables.transform_keys(&:to_s))

      _out, errors, status = Open3.capture3(environment, RbConfig.ruby, "-I#{GEM}/lib", "-I#{GEM}/test",
                                            "#{GEM}/test/dummy/probe.rb", *Array(as))

      raise "The dummy application did not boot (#{status.exitstatus}):\n#{errors}" unless File.exist?(report)

      JSON.parse(File.read(report), symbolize_names: true)
    end
  end
end
