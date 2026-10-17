require "active_record"
require "stateless_mcp/rails"

module StatelessMcp
  module Rails
    # Keyset paging for ActiveRecord, newest first. Optional, so neither gem
    # depends on ActiveRecord: an app that wants it requires this file and
    # includes the module beside StatelessMcp::Rails::Controller.
    #
    #   require "stateless_mcp/rails/active_record"
    #
    #   class Mcp::BaseController < ActionController::API
    #     include StatelessMcp::Rails::Controller
    #     include StatelessMcp::Rails::RecordPagination
    #   end
    module RecordPagination
      private

      # One page of records, newest first by (created_at, id), and the
      # next_cursor for the page after. Each page continues after the last
      # record of the one before, so a deep page costs the same as the first
      # and records added meanwhile don't shift it.
      def paginate(records, limit: page_limit)
        records = records.reorder(created_at: :desc, id: :desc)
        records = after_cursor(records, *Cursor.decode(tool_params[:cursor], count: 2)) if tool_params[:cursor].present?
        rows = records.limit(limit + 1).to_a
        page = rows.first(limit)
        [page, (Cursor.encode(page.last.created_at.iso8601(6), page.last.id) if rows.size > limit)]
      end

      # The id keeps its JSON type, so integer and string keys both work.
      def after_cursor(records, created_at, id)
        raise Cursor::Invalid unless id.is_a?(Integer) || id.is_a?(String)
        created_at = Time.iso8601(created_at.to_s)
        records.where(created_at: ...created_at).or(records.where(created_at: created_at, id: ...id))
      rescue ArgumentError
        raise Cursor::Invalid
      end
    end
  end
end
