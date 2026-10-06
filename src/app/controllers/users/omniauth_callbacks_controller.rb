class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # You should configure your model like this:
  # devise :omniauthable, omniauth_providers: [:twitter]

  # You should also create an action method in this controller like this:
  def facebook
    auth = request.env["omniauth.auth"]
    guest = guest_user
    @user = User.from_omniauth(auth, guest, calculator_nationality)

    if @user.persisted?
      sign_in @user, :event => :authentication #this will throw if @user is not activated
      session.delete(:guest_user_id)
      session.delete(:current_person_id)
      session.delete(:calculator_nationality_id)
      set_flash_message(:notice, :success, :kind => "Facebook") if is_navigational_format?
      redirect_to visits_path
    else
      session["devise.facebook_data"] = request.env["omniauth.auth"]
      redirect_to new_user_registration_path
    end

  end

  # More info at:
  # https://github.com/plataformatec/devise#omniauth

  # GET|POST /resource/auth/twitter
  def passthru
    super
  end

  # GET|POST /users/auth/twitter/callback
  def failure
    super
  end

  protected

  # The path used when omniauth fails
  def after_omniauth_failure_path_for(scope)
    super(scope)
  end
end
