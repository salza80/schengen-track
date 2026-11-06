module Public
  class VisitsController < ::VisitsController
    private

    def public_calculator_index?
      true
    end
  end
end
