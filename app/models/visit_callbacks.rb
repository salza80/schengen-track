class VisitCallbacks

  def self.after_save(visit)
    return if visit.no_schengen_callback
    calc = SchengenCalculator.new(visit)
    calc.execute_after_save
   
  end

  def self.after_destroy(visit)
    calc = SchengenCalculator.new(visit)
    calc.execute_after_destroy
  end

  def self.after_update(visit)
    return if visit.no_schengen_callback
    calc = SchengenCalculator.new(visit)
    calc.execute_after_save
  end
end



