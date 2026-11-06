module Public
  class DaysController < ::DaysController
    private

    def public_calculator_index?
      true
    end
  end
end
