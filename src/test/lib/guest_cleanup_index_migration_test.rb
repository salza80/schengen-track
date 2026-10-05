require 'test_helper'
require 'minitest/mock'
require Rails.root.join('db/migrate/20261005120000_add_guest_cleanup_index')

class GuestCleanupMigrationRecord < ActiveRecord::Base
  self.abstract_class = true
end

# Concurrent indexes cannot run inside transactional fixtures. A separate
# connection and disposable schema isolate these tests from application data.
class GuestCleanupIndexMigrationTest < Minitest::Test
  def setup
    @schema = "guest_cleanup_index_test_#{SecureRandom.hex(8)}"
    GuestCleanupMigrationRecord.establish_connection(ActiveRecord::Base.connection_db_config.configuration_hash)
    @connection = GuestCleanupMigrationRecord.connection
    @connection.execute("CREATE SCHEMA #{@connection.quote_table_name(@schema)}")
    @connection.schema_search_path = @schema
    @connection.create_table(:users) do |t|
      t.boolean :guest
      t.datetime :updated_at
    end
    @connection.execute("SET statement_timeout = '120s'")
  end

  def teardown
    @connection&.execute("DROP SCHEMA #{@connection.quote_table_name(@schema)} CASCADE") if @schema
    GuestCleanupMigrationRecord.remove_connection
  end

  def test_builds_index_and_preserves_timeout_on_rerun
    migrate
    assert_valid_index
    index_oid = @connection.select_value("SELECT #{ @connection.quote(AddGuestCleanupIndex::INDEX_NAME) }::regclass::oid")
    migrate
    assert_valid_index
    assert_equal index_oid, @connection.select_value("SELECT #{ @connection.quote(AddGuestCleanupIndex::INDEX_NAME) }::regclass::oid")
    assert_equal '2min', @connection.select_value('SHOW statement_timeout')
  end

  def test_recovers_an_invalid_concurrent_index
    @connection.execute("INSERT INTO users (guest, updated_at) VALUES (true, '2020-01-01'), (true, '2020-01-01')")
    assert_raises(ActiveRecord::RecordNotUnique) do
      @connection.add_index(:users, [:guest, :updated_at], name: AddGuestCleanupIndex::INDEX_NAME,
                            unique: true, algorithm: :concurrently)
    end
    refute cleanup_index.valid?

    migrate

    assert_valid_index
    assert_equal '2min', @connection.select_value('SHOW statement_timeout')
  end

  def test_restores_timeout_when_index_creation_fails
    migration = AddGuestCleanupIndex.new
    migration.stub(:connection, @connection) do
      @connection.stub(:add_index, ->(*) { raise 'forced index failure' }) do
        assert_raises(RuntimeError) { migration.up }
      end
    end
    assert_equal '2min', @connection.select_value('SHOW statement_timeout')
  end

  private

  def migrate
    AddGuestCleanupIndex.new.stub(:connection, @connection) { |migration| migration.up }
  end

  def cleanup_index
    @connection.indexes(:users).find { |index| index.name == AddGuestCleanupIndex::INDEX_NAME }
  end

  def assert_valid_index
    assert cleanup_index.valid?
    assert_equal %w[guest updated_at], cleanup_index.columns
    refute cleanup_index.unique
  end
end
