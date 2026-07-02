require 'test_helper'
require 'timeout'
require Rails.root.join('lib/lambda/task_executor')

class LambdaTaskExecutorTest < ActiveSupport::TestCase
  test 'run_rake invokes no-argument tasks without hanging' do
    task_name = "test:lambda_task_executor_no_args_#{SecureRandom.hex(8)}"
    invoked = false
    Rake::Task.define_task(task_name) { invoked = true }

    Timeout.timeout(1) do
      Lambda::TaskExecutor.send(:run_rake, task_name)
    end

    assert invoked
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
