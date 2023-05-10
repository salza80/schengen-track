class RemoveSchengenDays < ActiveRecord::Migration[5.1]
  def change
    remove_column :visits, :schengen_days, :integer
  end
end
