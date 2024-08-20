# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater"
require "dependabot/package_manager"
require "dependabot/notices"
require "dependabot/service"

RSpec.describe Dependabot::Updater::PullRequestHelpers do
  let(:dummy_class) do
    Class.new do
      include Dependabot::Updater::PullRequestHelpers

      attr_accessor :notices, :service

      def initialize(service = nil)
        @notices = []
        @service = service
      end
    end
  end

  let(:dummy_instance) { dummy_class.new(service) }

  let(:service) { instance_double(Dependabot::Service) }

  let(:package_manager) do
    Class.new(Dependabot::PackageManagerBase) do
      def name
        "bundler"
      end

      def version
        Dependabot::Version.new("1")
      end

      def deprecated_versions
        [Dependabot::Version.new("1")]
      end

      def supported_versions
        [Dependabot::Version.new("2"), Dependabot::Version.new("3")]
      end
    end.new
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?).with(:add_deprecation_warn_to_pr_message).and_return(true)
    allow(service).to receive(:record_update_job_warn)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#add_deprecation_notice" do
    context "when package manager is provided and is deprecated" do
      it "adds a deprecation notice to the notices array" do
        expect do
          dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, package_manager: package_manager)
        end
          .to change { dummy_instance.notices.size }.by(1)

        notice = dummy_instance.notices.first
        expect(notice.mode).to eq("WARN")
        expect(notice.type).to eq("bundler_deprecated_warn")
        expect(notice.package_manager_name).to eq("bundler")
      end
    end

    context "when package manager is not provided" do
      it "does not add a deprecation notice to the notices array" do
        expect { dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, package_manager: nil) }
          .not_to(change { dummy_instance.notices.size })
      end
    end

    context "when package manager is not deprecated" do
      let(:package_manager) do
        Class.new(Dependabot::PackageManagerBase) do
          def name
            "bundler"
          end

          def version
            Dependabot::Version.new("2")
          end

          def deprecated_versions
            [Dependabot::Version.new("1")]
          end

          def supported_versions
            [Dependabot::Version.new("2"), Dependabot::Version.new("3")]
          end
        end.new
      end

      it "does not add a deprecation notice to the notices array" do
        expect do
          dummy_instance.add_deprecation_notice(notices: dummy_instance.notices, package_manager: package_manager)
        end
          .not_to(change { dummy_instance.notices.size })
      end
    end
  end

  describe "#send_deprecation_notice" do
    context "when deprecation notice is generated" do
      let(:deprecation_notice) do
        Dependabot::Notice.new(
          mode: "WARN",
          type: "bundler_deprecated_warn",
          package_manager_name: "bundler",
          title: "Package manager deprecation notice",
          message: "Dependabot will stop supporting `bundler v1`!\n" \
                   "Please upgrade to one of the following versions: `v2`, or `v3`.\n",
          markdown: "> [!WARNING]\n> Dependabot will stop supporting `bundler v1`!\n>\n" \
                    "> Please upgrade to one of the following versions: `v2`, or `v3`.\n>\n"
        )
      end

      it "logs the deprecation notice and records it as a warning" do
        expect(Dependabot.logger).to receive(:warn).with(deprecation_notice.message)
        expect(service).to receive(:record_update_job_warn).with(
          warn_type: deprecation_notice.type,
          warn_title: deprecation_notice.title,
          warn_message: deprecation_notice.message
        )

        dummy_instance.send_deprecation_notice(package_manager)
      end
    end

    context "when no deprecation notice is generated" do
      before do
        allow(dummy_instance).to receive(:create_deprecation_notice).and_return(nil)
      end

      it "does not log or record any warnings" do
        expect(Dependabot.logger).not_to receive(:warn)
        expect(service).not_to receive(:record_update_job_warn)

        dummy_instance.send_deprecation_notice(package_manager)
      end
    end

    context "when an error occurs during sending deprecation notice" do
      before do
        allow(dummy_instance).to receive(:create_deprecation_notice).and_raise(StandardError, "Unexpected error")
      end

      it "logs an error message" do
        expect(Dependabot.logger).to receive(:error).with(
          "Failed to send package manager deprecation notice warning: Unexpected error"
        )

        dummy_instance.send_deprecation_notice(package_manager)
      end
    end
  end
end
