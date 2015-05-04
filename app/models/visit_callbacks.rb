class VisitCallbacks

  def self.after_save(visit)
    return if visit.no_schengen_callback
    calc = SchengenCalculator.new(visit)
    calc.calculate_schengen
   
  end

  def self.after_destroy(visit)
    calc = SchengenCalculator.new(visit)
    calc.calculate_schengen
  end

  def self.after_update(visit)
    return if visit.no_schengen_callback
    calc = SchengenCalculator.new(visit)
    calc.calculate_schengen
  end
end



