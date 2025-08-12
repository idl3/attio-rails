# frozen_string_literal: true

module Attio
  module Rails
    module Concerns
      module Dealable
        extend ActiveSupport::Concern

        included do
          after_commit :sync_deal_to_attio, on: %i[create update], if: :should_sync_deal?
          after_commit :remove_deal_from_attio, on: :destroy, if: :should_remove_deal?

          class_attribute :attio_deal_configuration, instance_writer: false, default: nil
          class_attribute :attio_pipeline_id, instance_writer: false, default: nil
          class_attribute :attio_stage_field, instance_writer: false, default: nil
          class_attribute :attio_value_field, instance_writer: false, default: nil
          class_attribute :attio_deal_callbacks, instance_writer: false, default: {}
        end

        class_methods do
          def attio_deal_config(pipeline_id: nil, &block)
            if block_given? || pipeline_id
              self.attio_deal_configuration = DealConfig.new(self)
              attio_deal_configuration.instance_eval(&block) if block_given?
              self.attio_pipeline_id = pipeline_id if pipeline_id
            end
            attio_deal_configuration
          end

          def sync_all_deals_to_attio(**options)
            BulkSync.perform(
              all,
              object_type: "deals",
              transform: :to_attio_deal,
              **options
            )
          end
        end

        def sync_deal_to_attio
          run_deal_callback(:before_sync)

          if Attio::Rails.background_sync?
            AttioSyncJob.perform_later(
              model_name: self.class.name,
              model_id: id,
              action: :sync_deal
            )
          else
            sync_deal_to_attio_now
          end
        rescue StandardError => e
          handle_deal_sync_error(e)
        end

        def sync_deal_to_attio_now
          client = Attio::Rails.client
          return unless client.respond_to?(:deals)

          # Run before callback
          if respond_to?(:before_attio_deal_sync, true)
            before_attio_deal_sync
          end

          deal_data = to_attio_deal

          result = if attio_deal_id.present?
                     # Check for special cases
                     if stage_changed?
                       begin
                         client.deals.update(id: attio_deal_id, data: { stage_id: stage_id })
                       rescue StandardError => e
                         Attio::Rails.logger.error "Failed to update deal stage: #{e.message}"
                         raise
                       end
                     elsif respond_to?(:status) && status == "won"
                       begin
                         client.deals.update(id: attio_deal_id, data: { status: "won", closed_date: closed_date })
                       rescue StandardError => e
                         Attio::Rails.logger.error "Failed to mark deal as won: #{e.message}"
                         raise
                       end
                     elsif respond_to?(:status) && status == "lost"
                       begin
                         client.deals.update(id: attio_deal_id, data: { status: "lost", lost_reason: lost_reason })
                       rescue StandardError => e
                         Attio::Rails.logger.error "Failed to mark deal as lost: #{e.message}"
                         raise
                       end
                     else
                       client.deals.update(id: attio_deal_id, data: deal_data)
                     end
                   else
                     response = client.deals.create(data: deal_data)
                     update_column(:attio_deal_id, response[:id]) if respond_to?(:attio_deal_id=) && response[:id]
                     response
                   end

          # Run after callback
          if respond_to?(:after_attio_deal_sync, true)
            after_attio_deal_sync(result)
          end
          
          run_deal_callback(:after_sync, result)
          result
        end

        def remove_deal_from_attio
          return unless attio_deal_id.present?

          if Attio::Rails.background_sync?
            AttioSyncJob.perform_later(
              model_name: self.class.name,
              model_id: id,
              action: :delete_deal,
              attio_deal_id: attio_deal_id
            )
          else
            remove_deal_from_attio_now
          end
        rescue StandardError => e
          Attio::Rails.logger.error "Failed to delete deal from Attio: #{e.message}"
          raise if ::Rails.env.development?
        end

        def remove_deal_from_attio_now
          return unless attio_deal_id.present?

          client = Attio::Rails.client
          return unless client.respond_to?(:deals)

          client.deals.delete(id: attio_deal_id)
        end

        def mark_as_won!(won_date: Time.current, actual_value: nil)
          transaction do
            update!(status: "won", closed_date: won_date)

            if attio_deal_id.present?
              client = Attio::Rails.client
              if client.respond_to?(:deals)
                client.deals.mark_won(
                  id: attio_deal_id,
                  won_date: won_date,
                  actual_value: actual_value || deal_value
                )
              end
            end

            run_deal_callback(:on_won)
          end
        end

        def mark_as_lost!(lost_reason: nil, lost_date: Time.current)
          transaction do
            update!(status: "lost", closed_date: lost_date, lost_reason: lost_reason)

            if attio_deal_id.present?
              client = Attio::Rails.client
              if client.respond_to?(:deals)
                client.deals.mark_lost(
                  id: attio_deal_id,
                  lost_reason: lost_reason,
                  lost_date: lost_date
                )
              end
            end

            run_deal_callback(:on_lost)
          end
        end

        def update_stage!(new_stage_id)
          transaction do
            update!(current_stage_id: new_stage_id)

            if attio_deal_id.present?
              client = Attio::Rails.client
              if client.respond_to?(:deals)
                client.deals.update_stage(
                  id: attio_deal_id,
                  stage_id: new_stage_id
                )
              end
            end

            run_deal_callback(:on_stage_change, new_stage_id)
          end
        end

        def to_attio_deal
          config = self.class.attio_deal_configuration
          
          data = {
            name: deal_name,
            value: deal_value,
            pipeline_id: pipeline_id,
          }

          # Include stage_id if available
          if self.class.attio_stage_field.present? && respond_to?(self.class.attio_stage_field)
            data[:stage_id] = send(self.class.attio_stage_field)
          elsif respond_to?(:stage_id) && stage_id
            data[:stage_id] = stage_id
          elsif respond_to?(:status) && status
            data[:stage_id] = status
          end

          # Add company field using configured name
          if config&.company_field_name
            field_name = config.company_field_name
            data[:company_id] = send(field_name) if respond_to?(field_name) && send(field_name)
          elsif respond_to?(:company_attio_id) && company_attio_id
            data[:company_id] = company_attio_id
          end

          # Add owner field using configured name
          if config&.owner_field_name
            field_name = config.owner_field_name
            data[:owner_id] = send(field_name) if respond_to?(field_name) && send(field_name)
          elsif respond_to?(:owner_attio_id) && owner_attio_id
            data[:owner_id] = owner_attio_id
          end

          # Add expected close date using configured name
          if config&.expected_close_date_field_name
            field_name = config.expected_close_date_field_name
            data[:expected_close_date] = send(field_name) if respond_to?(field_name) && send(field_name)
          elsif respond_to?(:expected_close_date) && expected_close_date
            data[:expected_close_date] = expected_close_date
          end

          if config&.transform_method
            case config.transform_method
            when Proc
              config.transform_method.call(data, self)
            when Symbol, String
              send(config.transform_method, data)
            else
              data
            end
          else
            data
          end
        end

        def should_sync_deal?
          return false unless Attio::Rails.sync_enabled?
          return false unless pipeline_id.present?

          if attio_deal_configuration&.sync_condition
            case attio_deal_configuration.sync_condition
            when Proc
              if attio_deal_configuration.sync_condition.arity == 1
                attio_deal_configuration.sync_condition.call(self)
              else
                instance_exec(&attio_deal_configuration.sync_condition)
              end
            when Symbol, String
              send(attio_deal_configuration.sync_condition)
            else
              true
            end
          else
            true
          end
        end

        def should_remove_deal?
          attio_deal_id.present? && Attio::Rails.sync_enabled?
        end

        # Aliases for compatibility
        def sync_to_attio
          sync_deal_to_attio
        end

        def remove_from_attio
          remove_deal_from_attio
        end

        private

        def stage_changed?
          return false unless respond_to?(:current_stage_id) && respond_to?(:stage_id)
          return false if current_stage_id.nil? || stage_id.nil?
          current_stage_id != stage_id
        end

        def deal_name
          if attio_deal_configuration&.name_field
            send(attio_deal_configuration.name_field)
          elsif respond_to?(:name)
            name
          elsif respond_to?(:title)
            title
          else
            "#{self.class.name} ##{id}"
          end
        end

        private def deal_value
          if attio_deal_configuration&.value_field
            send(attio_deal_configuration.value_field)
          elsif respond_to?(:value)
            value
          elsif respond_to?(:amount)
            amount
          else
            0
          end
        end

        private def pipeline_id
          self.class.attio_pipeline_id || attio_deal_configuration&.pipeline_id
        end

        def current_stage_id
          if self.class.attio_stage_field.present? && respond_to?(self.class.attio_stage_field)
            send(self.class.attio_stage_field)
          elsif respond_to?(:stage_id)
            stage_id
          elsif respond_to?(:status)
            status
          end
        end

        private def run_deal_callback(callback_name, *args)
          callback = attio_deal_configuration&.callbacks&.dig(callback_name)
          return unless callback

          case callback
          when Proc
            instance_exec(*args, &callback)
          when Symbol, String
            send(callback, *args)
          end
        end

        private def handle_deal_sync_error(error)
          if attio_deal_configuration&.error_handler
            case attio_deal_configuration.error_handler
            when Proc
              instance_exec(error, &attio_deal_configuration.error_handler)
            when Symbol, String
              send(attio_deal_configuration.error_handler, error)
            end
          else
            Attio::Rails.logger.error "Failed to sync deal to Attio: #{error.message}"
            raise if ::Rails.env.development?
          end
        end

        class DealConfig
          attr_reader :sync_condition, :transform_method, :error_handler, :callbacks,
                      :company_field_name, :owner_field_name, :expected_close_date_field_name

          def initialize(model_class)
            @model_class = model_class
            @callbacks = {}
            @pipeline_id = nil
            @name_field = nil
            @value_field = nil
            @stage_field = nil
            @company_field_name = nil
            @owner_field_name = nil
            @expected_close_date_field_name = nil
          end

          def pipeline_id(value = nil)
            if value
              @pipeline_id = value
              @model_class.attio_pipeline_id = value
            else
              @pipeline_id
            end
          end

          def name_field(field = nil)
            if field
              @name_field = field
            else
              @name_field
            end
          end

          def value_field(field = nil)
            if field
              @value_field = field
              @model_class.attio_value_field = field
            else
              @value_field
            end
          end

          def stage_field(field = nil)
            if field
              @stage_field = field
              @model_class.attio_stage_field = field
            else
              @stage_field
            end
          end

          def sync_if(condition)
            @sync_condition = condition
          end

          def transform(method_or_block = nil, &block)
            @transform_method = block || method_or_block
          end

          def on_error(handler)
            @error_handler = handler
          end

          def before_sync(method_or_block = nil, &block)
            @callbacks[:before_sync] = block || method_or_block
          end

          def after_sync(method_or_block = nil, &block)
            @callbacks[:after_sync] = block || method_or_block
          end

          def on_won(method_or_block = nil, &block)
            @callbacks[:on_won] = block || method_or_block
          end

          def on_lost(method_or_block = nil, &block)
            @callbacks[:on_lost] = block || method_or_block
          end

          def on_stage_change(method_or_block = nil, &block)
            @callbacks[:on_stage_change] = block || method_or_block
          end

          def company_field(field = nil)
            if field
              @company_field_name = field
            else
              @company_field_name
            end
          end

          def owner_field(field = nil)
            if field
              @owner_field_name = field
            else
              @owner_field_name
            end
          end

          def expected_close_date_field(field = nil)
            if field
              @expected_close_date_field_name = field
            else
              @expected_close_date_field_name
            end
          end

          # Alias for transform to match test expectations
          def transform_fields(method_or_block = nil, &block)
            transform(method_or_block, &block)
          end
        end
      end
    end
  end
end
