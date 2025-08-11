# frozen_string_literal: true

module Attio
  module Rails
    module RSpec
      module Matchers
        ::RSpec::Matchers.define :sync_to_attio do |expected|
          match do |actual|
            return false unless actual.class.respond_to?(:attio_object_type)

            if expected
              actual.class.attio_object_type == expected[:object] || expected[:object_type]
            else
              actual.class.attio_object_type.present?
            end
          end

          failure_message do |actual|
            if actual.class.respond_to?(:attio_object_type)
              expected_obj = expected[:object] || expected[:object_type]
              actual_obj = actual.class.attio_object_type
              "expected #{actual.class} to sync to Attio object '#{expected_obj}' but syncs to '#{actual_obj}'"
            else
              "expected #{actual.class} to include Attio::Rails::Concerns::Syncable"
            end
          end

          failure_message_when_negated do |actual|
            "expected #{actual.class} not to sync to Attio"
          end

          description do
            "sync to Attio"
          end
        end

        ::RSpec::Matchers.define :have_attio_attribute do |attio_attr|
          match do |actual|
            return false unless actual.class.respond_to?(:attio_attribute_mapping)

            mapping = actual.class.attio_attribute_mapping
            if @mapped_to
              mapping[attio_attr] == @mapped_to
            else
              mapping.key?(attio_attr)
            end
          end

          chain :mapped_to do |local_attr|
            @mapped_to = local_attr
          end

          failure_message do |actual|
            if actual.class.respond_to?(:attio_attribute_mapping)
              mapping = actual.class.attio_attribute_mapping
              if @mapped_to
                actual_mapping = mapping[attio_attr]
                "expected #{actual.class} to map Attio attribute '#{attio_attr}' to '#{@mapped_to}' " \
                  "but it maps to '#{actual_mapping}'"
              else
                available_attrs = mapping.keys.join(", ")
                "expected #{actual.class} to have Attio attribute '#{attio_attr}' but has #{available_attrs}"
              end
            else
              "expected #{actual.class} to include Attio::Rails::Concerns::Syncable"
            end
          end

          description do
            if @mapped_to
              "have Attio attribute '#{attio_attr}' mapped to '#{@mapped_to}'"
            else
              "have Attio attribute '#{attio_attr}'"
            end
          end
        end

        ::RSpec::Matchers.define :enqueue_attio_sync_job do # rubocop:disable Metrics/BlockLength
          supports_block_expectations

          match do |block|
            initial_jobs = attio_sync_jobs.dup
            block.call
            new_jobs = attio_sync_jobs - initial_jobs
            @actual_count = new_jobs.size

            if @expected_count
              @actual_count == @expected_count
            elsif @expected_action
              new_jobs.any? { |job| job[:args].first["action"]["value"] == @expected_action.to_s }
            else
              @actual_count > 0
            end
          end

          chain :with_action do |action|
            @expected_action = action
          end

          chain :exactly do |count|
            @expected_count = count
          end

          failure_message do
            build_failure_message
          end

          failure_message_when_negated do
            "expected not to enqueue AttioSyncJob but #{@actual_count} were enqueued"
          end

          description do
            build_description
          end

          private def build_failure_message
            if @expected_count
              "expected to enqueue #{@expected_count} AttioSyncJob(s) but enqueued #{@actual_count}"
            elsif @expected_action
              "expected to enqueue AttioSyncJob with action '#{@expected_action}'"
            else
              "expected to enqueue AttioSyncJob but none were enqueued"
            end
          end

          private def build_description
            if @expected_count
              "enqueue #{@expected_count} AttioSyncJob(s)"
            elsif @expected_action
              "enqueue AttioSyncJob with action '#{@expected_action}'"
            else
              "enqueue AttioSyncJob"
            end
          end

          private def attio_sync_jobs
            ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
              job[:job] == AttioSyncJob
            end
          end
        end
      end
    end
  end
end
