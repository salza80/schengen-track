class RemoveOldSchengenCalcFromCountries < ActiveRecord::Migration[7.1]
  def change
    remove_column :countries, :old_schengen_calc, :boolean
  end
end
