class CreateApiRateLimits < ActiveRecord::Migration[7.1]
  def change
    create_table :api_rate_limits do |t|
      t.string :rate_limit_key, null: false
      t.string :scope, null: false
      t.string :identifier, null: false
      t.datetime :window_start, null: false
      t.datetime :expires_at, null: false
      t.integer :count, null: false, default: 0

      t.timestamps
    end

    add_index :api_rate_limits, :rate_limit_key, unique: true
    add_index :api_rate_limits, :expires_at
  end
end
