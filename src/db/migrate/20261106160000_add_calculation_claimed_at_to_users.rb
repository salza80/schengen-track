class AddCalculationClaimedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :calculation_claimed_at, :datetime
  end
end
