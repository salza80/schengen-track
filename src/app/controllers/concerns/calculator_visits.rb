# frozen_string_literal: true

module CalculatorVisits
  extend ActiveSupport::Concern

  private

  # Keep the supported presentation window without deleting stored history.
  # DraftPerson's empty collection must stay free of Active Record/schema work.
  def calculator_visits
    return current_person.visits unless current_person.persisted?

    @calculator_visits ||= current_person.visits.where(
      'entry_date >= :past AND (exit_date IS NULL OR exit_date <= :future)',
      past: Date.today - 20.years, future: Date.today + 20.years
    )
  end
end
