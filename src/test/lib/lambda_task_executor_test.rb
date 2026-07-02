require 'test_helper'
require Rails.root.join('lib/lambda/task_executor')

class LambdaTaskExecutorTest < ActiveSupport::TestCase
  setup do
    File.delete('/tmp/guest_cleanup_stats.json') if File.exist?('/tmp/guest_cleanup_stats.json')
  end

  teardown do
    File.delete('/tmp/guest_cleanup_stats.json') if File.exist?('/tmp/guest_cleanup_stats.json')
  end

  test 'guest cleanup keeps max_batches when limit_date is omitted' do
    old_guest = User.create!(
      email: 'old-guest@example.com',
      password: 'password',
      first_name: 'Old',
      last_name: 'Guest',
      nationality: countries(:Australia),
      guest: true
    )
    old_guest.update_columns(created_at: 45.days.ago, updated_at: 45.days.ago)

    result = Lambda::TaskExecutor.execute(
      'command' => 'guest_cleanup',
      'params' => { 'max_batches' => 5 }
    )

    assert_equal true, result[:success]
    assert_equal 1, result[:stats]['deleted']
    assert_equal 1, result[:stats]['batches']
    assert_equal 0, result[:stats]['remaining']
    assert_not User.exists?(old_guest.id)
  end
end
