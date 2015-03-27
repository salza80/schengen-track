class Personrenamecountryid < ActiveRecord::Migration
  def change
    rename_column :people, :country_id, :nationality_id
  end
end
