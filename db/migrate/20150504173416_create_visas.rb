class CreateVisas < ActiveRecord::Migration
  def change
    create_table :visas do |t|
      t.date :start_date
      t.date :end_date
      t.integer :no_entries
      t.text :visa_type
      t.references :person
      t.timestamps null: false
    end
    add_foreign_key :visas, :people
  end
end


