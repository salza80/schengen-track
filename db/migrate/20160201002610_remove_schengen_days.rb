class RemoveSchengenDays < ActiveRecord::Migration
  def change
    remove_column :visits, :schengen_days, :integer
  end
end
