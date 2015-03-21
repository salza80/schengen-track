class CreatePeople < ActiveRecord::Migration
  def change
    create_table :people do |t|
      t.string :first_name
      t.string :last_name
      t.references :country, index: true

      t.timestamps null: false
    end
    add_foreign_key :people, :countries
  end
end
