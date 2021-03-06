require "assert"

require "a-lint-runner"

class ALintRunner::Linter
  class UnitTests < Assert::Context
    desc "ALintRunner::Linter"
    setup do
      @unit_class = ALintRunner::Linter
    end
    subject { @unit_class }
  end

  class InitTests < UnitTests
    desc "when init"
    subject {
      @unit_class.new(
        name: name1,
        executable: executable1,
        extensions: [extension1]
      )
    }

    let(:name1) { Factory.string }
    let(:executable1) { Factory.string }
    let(:extension1) { ".rb" }
    let(:applicable_source_files) { ["app/file1.rb", "app/file2.rb"] }
    let(:not_applicable_source_file) { "app/file2.js" }
    let(:cli_option_name1) { Factory.string }
    let(:cli_abbrev1) { Factory.string(1) }

    should have_readers :name, :executable, :extensions
    should have_readers :cli_option_name, :cli_abbrev

    should "know its attributes" do
      assert_that(subject.name).equals(name1)
      assert_that(subject.executable).equals(executable1)
      assert_that(subject.extensions).equals([extension1])
      assert_that(subject.cli_option_name).equals(name1)
      assert_that(subject.cli_abbrev).equals(name1[0])

      linter =
        @unit_class.new(
          name: name1,
          executable: executable1,
          extensions: [extension1],
          cli_option_name: cli_option_name1,
          cli_abbrev: cli_abbrev1
        )
      assert_that(linter.cli_option_name).equals(cli_option_name1)
      assert_that(linter.cli_abbrev).equals(cli_abbrev1)
    end

    should "know if it is enabled and specifically enabled" do
      assert_that(subject.specifically_enabled?).is_false
      assert_that(subject.enabled?).is_true

      subject.specifically_enabled = nil
      assert_that(subject.specifically_enabled?).is_false
      assert_that(subject.enabled?).is_true

      subject.specifically_enabled = true
      assert_that(subject.specifically_enabled?).is_true
      assert_that(subject.enabled?).is_true

      subject.specifically_enabled = false
      assert_that(subject.specifically_enabled?).is_false
      assert_that(subject.enabled?).is_false
    end

    should "know its cmd_str given applicable source files" do
      assert_that(subject.cmd_str(applicable_source_files)).equals(
        "#{executable1} #{applicable_source_files.join(" ")}"
      )
    end

    should "know its cmd_str given not applicable source files" do
      assert_that(subject.cmd_str([not_applicable_source_file])).is_nil
    end
  end
end
