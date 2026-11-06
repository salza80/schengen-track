# frozen_string_literal: true

module GuestCalculatorCapacity
  extend ActiveSupport::Concern

  included do
    around_create do |record, insert|
      GuestCalculations::Capacity.with_space_for(record, &insert)
    end
  end
end
