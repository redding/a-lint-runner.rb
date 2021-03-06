require "assert"

require "a-lint-runner"

class ALintRunner::Runner
  class UnitTests < Assert::Context
    desc "ALintRunner::Runner"
    setup do
      @unit_class = ALintRunner::Runner
    end
    subject{ @unit_class }
  end

  class InitSetupTests < UnitTests
    desc "when init"
    setup do
      Assert.stub(Dir, :pwd){ TEST_SUPPORT_PATH }
      @whitelisted_source_files = [
        "app/file1.rb",
        "app/file2.js",
        "app/file3.scss"
      ]

      @file_paths  = [""]
      @lint_output = ""
      @config      = ALintRunner::Config.new(StringIO.new(@lint_output))
      Assert.stub(ALintRunner, :config){ @config }
    end
    subject{ @runner }
  end

  class InitTests < InitSetupTests
    setup do
      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should have_readers :file_paths, :config

    should "know its attributes" do
      assert_that(subject.file_paths).equals(@file_paths)
      assert_that(subject.config).is_the_same_as(@config)
      assert_that(subject.execute?).is_true
      assert_that(subject.any_linters?).is_true
      assert_that(subject.dry_run?).is_false
      assert_that(subject.list?).is_false
      assert_that(subject.debug?).is_false
      assert_that(subject.changed_only?).is_false
      assert_that(subject.linters).equals(@config.linters)
      assert_that(subject.specified_source_files).equals(
        [
          "app",
          *@whitelisted_source_files,
          "factory.rb"
        ]
      )

      assert_that(subject.cmds).equals(
        subject.linters.reduce({}) { |acc, linter|
          acc[linter.cli_option_name] =
            linter.cmd_str(subject.specified_source_files)
          acc
        }
      )
    end

    should "know its enabled linters" do
      assert_that(subject.any_specifically_enabled_linters?).is_false
      assert_that(subject.specifically_enabled_linters).equals([])
      assert_that(subject.enabled_linters).equals(subject.linters)
    end

    should "know its enabled linters given specifically enabled linters" do
      @config.linters.first.specifically_enabled = true

      assert_that(subject.any_specifically_enabled_linters?).is_true
      assert_that(subject.specifically_enabled_linters).equals(
        [ @config.linters.first])
      assert_that(subject.enabled_linters).equals(subject.linters)
    end

    should "know its enabled linters given specifically disabled linters" do
      @config.linters.first.specifically_enabled = false

      assert_that(subject.any_specifically_enabled_linters?).is_false
      assert_that(subject.specifically_enabled_linters).equals([])
      assert_that(subject.enabled_linters).equals(subject.linters[1..-1])
    end

    should "know its source files given blacklisted files" do
      MuchStub.(@config, :ignored_files) { ["factory.rb"] }

      assert_that(subject.specified_source_files).equals(
        [
          "app",
          *@whitelisted_source_files,
        ]
      )
    end
  end

  class DryRunTests < InitSetupTests
    desc "and configured to dry run"
    setup do
      Assert.stub(@config, :dry_run){ true }

      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should "output the cmd str to stdout and but not execute it" do
      assert_that(subject.execute?).is_false
      assert_that(subject.dry_run?).is_true

      subject.run
      subject.cmds.values.each do |cmd|
        assert_that(@lint_output).includes(cmd)
      end
    end
  end

  class SpecificLintersEnabledTests < InitSetupTests
    desc "and configured with specific linters enabled"
    setup do
      Assert.stub(@config, :dry_run){ true }
      @config.linters.first.specifically_enabled = true

      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should "run only the specifically enabled linters" do
      subject.run

      linter_names = subject.specifically_enabled_linters.map(&:cli_option_name)
      linter_names.each do |name|
        assert_that(@lint_output).includes(subject.cmds[name])
      end
    end
  end

  class SpecificLintersDisabledTests < InitSetupTests
    desc "and configured with specific linters disabled"
    setup do
      Assert.stub(@config, :dry_run){ true }
      @config.linters.first.specifically_enabled = false

      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should "run only the specifically enabled linters" do
      subject.run

      linter_names = subject.enabled_linters.map(&:cli_option_name)
      linter_names.each do |name|
        assert_that(@lint_output).includes(subject.cmds[name])
      end
    end
  end

  class ListTests < InitSetupTests
    desc "and configured to list"
    setup do
      Assert.stub(@config, :list){ true }

      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should "list out the lint files to stdout and not execute the cmd str" do
      assert_that(subject.execute?).is_false
      assert_that(subject.list?).is_true

      subject.run
      assert_that(@lint_output).includes(subject.specified_source_files.join("\n"))
    end
  end

  class ChangedOnlySetupTests < InitSetupTests
    setup do
      @changed_ref = Factory.string
      Assert.stub(@config, :changed_ref){ @changed_ref }
      Assert.stub(@config, :changed_only){ true }
      Assert.stub(@config, :dry_run){ true }

      @changed_source_file = @whitelisted_source_files.sample
      @git_cmd_used = nil
      Assert.stub(ALintRunner::GitChangedFiles, :new) do |*args|
        @git_cmd_used = ALintRunner::GitChangedFiles.cmd(*args)
        ALintRunner::ChangedResult.new(@git_cmd_used, [@changed_source_file])
      end

      @file_paths = @whitelisted_source_files
    end
  end

  class ChangedOnlyTests < ChangedOnlySetupTests
    desc "and configured in changed only mode"
    setup do
      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should "only run the source files that have changed" do
      assert_that(subject.changed_only?).is_true
      assert_that(subject.specified_source_files).equals([@changed_source_file])

      assert_that(@git_cmd_used).equals(
        "git diff --no-ext-diff --name-only #{@changed_ref} "\
        "-- #{@file_paths.join(" ")} && "\
        "git ls-files --others --exclude-standard "\
        "-- #{@file_paths.join(" ")}"
      )
    end
  end

  class DebugTests < ChangedOnlySetupTests
    desc "and configured in debug mode"
    setup do
      Assert.stub(@config, :debug){ true }

      @runner = @unit_class.new(@file_paths, config: @config)
    end

    should "output detailed debug info" do
      changed_result = ALintRunner::GitChangedFiles.new(@config, @file_paths)
      changed_cmd = changed_result.cmd
      changed_files_count = changed_result.files.size
      changed_files_lines = changed_result.files.map{ |f| "[DEBUG]   #{f}" }

      assert_that(subject.execute?).is_false

      subject.run
      assert_that(@lint_output).includes("[DEBUG] Lookup changed source files...")
      assert_that(@lint_output).includes(
        "[DEBUG]   `#{changed_cmd}`\n"\
        "[DEBUG] #{changed_files_count} specified source files:\n"\
        "#{changed_files_lines.join("\n")}\n"\
      )
    end
  end
end
