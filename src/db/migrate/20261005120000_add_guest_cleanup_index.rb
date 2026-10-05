class AddGuestCleanupIndex < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_guest_updated_at'.freeze
  INDEX_STATEMENT_TIMEOUT = '600s'.freeze

  def up
    previous_timeout = connection.select_value('SHOW statement_timeout')
    connection.execute("SET statement_timeout = '#{INDEX_STATEMENT_TIMEOUT}'")
    existing_index = connection.indexes(:users).find { |index| index.name == INDEX_NAME }
    return if existing_index&.valid?

    # A canceled concurrent build leaves an invalid index behind. Remove it
    # before retrying instead of skipping it or failing with DuplicateTable.
    remove_index :users, name: INDEX_NAME, algorithm: :concurrently if existing_index
    add_index :users, [:guest, :updated_at], name: INDEX_NAME, algorithm: :concurrently
  ensure
    connection.execute("SET statement_timeout = #{connection.quote(previous_timeout)}") if previous_timeout
  end

  def down
    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end
