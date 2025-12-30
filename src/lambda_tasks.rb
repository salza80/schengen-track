# frozen_string_literal: true

require 'json'
require_relative './config/environment'
require_relative './lib/lambda/task_executor'

module LambdaTasks
  module_function

  def handler(event:, context:)
    result = Lambda::TaskExecutor.execute(event || {})
    { statusCode: 200, body: JSON.generate(result) }
  rescue => e
    error_response = { success: false, error: e.message }
    { statusCode: 500, body: JSON.generate(error_response) }
  end
end
