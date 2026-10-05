class AddGuestCleanupIndex < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_guest_updated_at'.freeze
  INDEX_STATEMENT_TIMEOUT = '600s'.freeze

  def up
    connection.execute("SET statement_timeout = '#{INDEX_STATEMENT_TIMEOUT}'")
    add_index :users, [:guest, :updated_at], name: INDEX_NAME, algorithm: :concurrently
  ensure
    connection.execute('RESET statement_timeout')
  end

  def down
    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end
