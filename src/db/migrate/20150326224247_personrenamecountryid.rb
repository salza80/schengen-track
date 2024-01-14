class Personrenamecountryid < ActiveRecord::Migration[5.1]
  def change
    rename_column :people, :country_id, :nationality_id
  end
end
