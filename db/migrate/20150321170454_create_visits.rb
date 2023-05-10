class CreateVisits < ActiveRecord::Migration[5.1]
  def change
    create_table :visits do |t|
      t.date :entry_date
      t.date :exit_date
      t.integer :schengen_days
      t.references :country, index: true
      t.references :person

      t.timestamps null: false
    end
    add_foreign_key :visits, :countries
  end
end
