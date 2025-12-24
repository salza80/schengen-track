class Users::SessionsController < Devise::SessionsController
  # Skip set_cache_cookie during login to prevent session modification that interferes with CSRF
  # The set_cache_cookie before_action from ApplicationController modifies the session by
  # calling guest_user, which conflicts with Devise's session regeneration on successful login
  skip_before_action :set_cache_cookie, only: [:create]

#   before_action :configure_sign_in_params, only: [:create]

#   # GET /resource/sign_in
#   def new
#     super
#   end

#   # POST /resource/sign_in
#   def create
#     super
#   end

#   # DELETE /resource/sign_out
#   def destroy
#     super
#   end

#   protected

#   # You can put the params you want to permit in the empty array.
#   def configure_sign_in_params
#     devise_parameter_sanitizer.for(:sign_in) << :attribute
#   end
end
