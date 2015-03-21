class CreateCountries < ActiveRecord::Migration
  def change
    create_table :countries do |t|
      t.string :name
      t.string :country_code

      t.timestamps null: false
    end
    add_index :countries, :country_code, unique: true
  end
end
