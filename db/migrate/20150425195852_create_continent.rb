class CreateContinent < ActiveRecord::Migration
  def change
    create_table :continents do |t|
      t.string :continent_code
      t.string :name
      t.timestamps null: false
    end
    add_index :continents, :continent_code, unique: true

    add_reference :countries, :continent,  index: true
    add_foreign_key :countries, :continents
  end
end
