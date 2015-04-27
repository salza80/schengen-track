class AlterCountries < ActiveRecord::Migration
  def change
    add_column :countries, :EU_memeber_state, :boolean
    add_column :countries, :visa_required, :string
    add_column :countries, :old_schengen_calc, :boolean
    add_column :countries, :additional_visa_waiver, :boolean
  end
end
