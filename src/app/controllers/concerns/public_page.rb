module PublicPage
  extend ActiveSupport::Concern

  EDGE_TTL = 30.days.to_i

  included do
    skip_before_action :restore_guest_calculation, :sync_session_hint_cookie
    before_action :prepare_public_page
  end

  private

  def prepare_public_page
    @public_static_page = true
    request.session_options[:skip] = true
    response.headers['Cache-Control'] = "public, max-age=0, s-maxage=#{EDGE_TTL}"
  end
end
