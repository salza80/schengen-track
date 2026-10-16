class CsrfTokensController < ApplicationController
  skip_before_action :restore_guest_calculation, :sync_session_hint_cookie
  skip_after_action :set_flash_hint
  before_action :set_private_calculator_cache

  def show
    render json: {
      param: request_forgery_protection_token,
      token: form_authenticity_token
    }
  end
end
