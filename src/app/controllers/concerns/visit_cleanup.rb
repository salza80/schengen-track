# frozen_string_literal: true

# Concern for cleaning up old visits beyond ±20 years from today
module VisitCleanup
  extend ActiveSupport::Concern

  private

  def cleanup_old_visits
    return unless current_user_or_guest_user

    cutoff_past = Date.today - 20.years
    cutoff_future = Date.today + 20.years

    deleted_count = current_user_or_guest_user.visits
                                               .where('entry_date < :past OR exit_date > :future',
                                                      past: cutoff_past,
                                                      future: cutoff_future)
                                               .delete_all

    if deleted_count.positive?
      Rails.logger.info "Cleaned up #{deleted_count} old visits for user #{current_user_or_guest_user.id}"
    end
  end
end
