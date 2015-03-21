class CreateVisits < ActiveRecord::Migration
  def change
    create_table :visits do |t|
      t.date :entry_date
      t.date :exit_date
      t.integer :schengen_days
      t.references :Country, index: true
      t.References :Person

      t.timestamps null: false
    end
    add_foreign_key :visits, :Countries
  end
end
