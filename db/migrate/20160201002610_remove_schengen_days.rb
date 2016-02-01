class RemoveSchengenDays < ActiveRecord::Migration
  def change
    remove_column :visits, :schengen_days
  end
end
