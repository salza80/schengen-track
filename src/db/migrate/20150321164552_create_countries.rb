class CreateCountries < ActiveRecord::Migration[5.1]
  def change
    create_table :countries do |t|
      t.string :name
      t.string :country_code
      t.date :schengen_start_date
      t.timestamps null: false
    end
    add_index :countries, :country_code, unique: true
  end
end
