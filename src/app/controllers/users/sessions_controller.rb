class Users::SessionsController < Devise::SessionsController
  # Skip set_cache_cookie during login/logout to prevent session modification that interferes with CSRF
  # The set_cache_cookie before_action from ApplicationController modifies the session by
  # calling guest_user, which conflicts with Devise's session regeneration during authentication
  skip_before_action :set_cache_cookie, only: [:create, :destroy]

  # Override create to update cache cookie after successful authentication
  # This ensures the cache_country_guest cookie is updated from "US_true" to "US_{random_hex}"
  # before the redirect, preventing cached pages with stale CSRF tokens from being served
  def create
    super do |resource|
      # After successful authentication, update the cache cookie
      # This happens after Devise's session regeneration, so it's safe
      if resource.persisted?
        set_cache_cookie
      end
    end
  end

  protected

  # Redirect to visits page after sign in (like Facebook OAuth does)
  # This ensures users land on an uncached page with fresh CSRF tokens
  def after_sign_in_path_for(resource)
    visits_path
  end
end
