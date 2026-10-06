class Users::SessionsController < Devise::SessionsController
  # Skip set_cache_cookie during login/logout to prevent session modification that interferes with CSRF
  # The set_cache_cookie before_action from ApplicationController modifies the session by
  # calling guest_user, which conflicts with Devise's session regeneration during authentication
  skip_before_action :set_cache_cookie, only: [:create, :destroy]

  # Override create to update cache cookie after successful authentication
  # This ensures the cache_country_guest cookie is updated from "US_true" to "US_{random_hex}"
  # before the redirect, preventing cached pages with stale CSRF tokens from being served
  def create
    guest_person_id = session[:current_person_id] if session[:guest_user_id]

    super do |resource|
      # After successful authentication, update the cache cookie
      # This happens after Devise's session regeneration, so it's safe
      if resource.persisted?
        resource.ensure_primary_person
        session[:guest_current_person_id] = guest_person_id if guest_person_id
        session.delete(:current_person_id)
        session.delete(:calculator_nationality_id)
        @current_user_or_guest_user = resource
        remove_instance_variable(:@current_person) if defined?(@current_person)
        set_cache_cookie
      end
    end
  end

  def destroy
    guest_id = session[:guest_user_id]
    guest_person_id = session[:guest_current_person_id]

    super do
      guest = User.find_by(id: guest_id, guest: true)
      if guest
        restored_person_id = guest.people.where(id: guest_person_id).pick(:id)
        restored_person_id ||= guest.people.find_by(is_primary: true)&.id || guest.people.first&.id
        session[:guest_user_id] = guest.id
        session[:current_person_id] = restored_person_id
      else
        session.delete(:guest_user_id)
        session.delete(:current_person_id)
      end
      session.delete(:guest_current_person_id)
      @current_user_or_guest_user = guest
      remove_instance_variable(:@current_person) if defined?(@current_person)
      set_cache_cookie
    end
  end

  protected

  # Redirect to visits page after sign in (like Facebook OAuth does)
  # This ensures users land on an uncached page with fresh CSRF tokens
  def after_sign_in_path_for(resource)
    visits_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    visits_path
  end
end
