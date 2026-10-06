class SessionHeadersController < ApplicationController
  skip_before_action :restore_guest_calculation, :sync_session_hint_cookie
  prepend_before_action :disable_header_caching

  def show
    notices = if flash[:notice].present? || flash[:alert].present?
                render_to_string(partial: 'layouts/notice')
              end
    flash.discard if notices

    unless current_user_or_guest_user && current_person
      # A nationality preference is valid calculator state, but it is not a
      # persisted person and therefore cannot produce a person menu.
      clear_session_hint unless selected_calculator_nationality
      # A deleted account can still have a confirmation to display. Commit the
      # consumed flash, without creating a guest or rendering a personal menu.
      return render json: { notice_html: notices } if notices

      request.session_options[:skip] = true
      return head :no_content
    end

    set_session_hint
    render json: { html: render_to_string(partial: 'layouts/user_menu'),
                   csrf_token: form_authenticity_token, notice_html: notices }
  end

  private

  def disable_header_caching
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Vary'] = 'Cookie'
  end

  # Never call guest_user or ensure_primary_person here. Even stale sessions
  # must not create accounts or people just to personalize an information page.
  def current_user_or_guest_user
    return @header_user if defined?(@header_user)

    @header_user = current_user
    @header_user ||= User.find_by(id: session[:guest_user_id], guest: true) if session[:guest_user_id]
    @header_user
  end

  def current_person
    return @header_person if defined?(@header_person)

    user = current_user_or_guest_user
    @header_person = user&.people&.find_by(id: session[:current_person_id]) if session[:current_person_id]
    @header_person ||= user&.people&.find_by(is_primary: true) || user&.people&.first
  end
end
