module PublicPage
  extend ActiveSupport::Concern

  included do
    skip_before_action :restore_guest_calculation, :sync_session_hint_cookie
    before_action :prepare_public_page
  end

  private

  def prepare_public_page
    @public_static_page = true
    request.session_options[:skip] = true
    expires_in 1.hour, public: true
  end
end
