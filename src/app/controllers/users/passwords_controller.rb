class Users::PasswordsController < Devise::PasswordsController
  include SensitiveTokenResponse

  rescue_from PasswordRecovery::Request::Throttled, with: :recovery_throttled
  rescue_from RateLimiters::DatabaseFixedWindow::Unavailable, with: :recovery_unavailable

  def create
    submitted = params[resource_name]
    email = submitted[:email] if submitted.is_a?(ActionController::Parameters)
    PasswordRecovery::Request.new(
      email: email, client_ip: request.get_header('schengen.client_ip').presence || request.remote_ip
    ).call

    respond_to do |format|
      format.html do
        set_flash_message!(:notice, :send_paranoid_instructions)
        redirect_to after_sending_reset_password_instructions_path_for(resource_name), status: :see_other
      end
      format.json { render json: { message: t('devise.passwords.send_paranoid_instructions') }, status: :accepted }
    end
  end

  private

  def recovery_throttled(error)
    response.set_header('Retry-After', error.retry_after.to_s)
    I18n.with_locale(route_locale || I18n.default_locale) do
      recovery_error('rate_limited', t('devise.passwords.rate_limited'), :too_many_requests)
    end
  end

  def recovery_unavailable
    response.set_header('Retry-After', '60')
    I18n.with_locale(route_locale || I18n.default_locale) do
      recovery_error('service_unavailable', t('devise.passwords.temporarily_unavailable'), :service_unavailable)
    end
  end

  def recovery_error(code, message, status)
    respond_to do |format|
      format.html { render plain: message, status: status }
      format.json { render json: { error: { code: code, message: message } }, status: status }
    end
  end
end
