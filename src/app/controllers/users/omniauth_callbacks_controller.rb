class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # You should configure your model like this:
  # devise :omniauthable, omniauth_providers: [:twitter]

  # You should also create an action method in this controller like this:
  def facebook
    auth = request.env["omniauth.auth"]
    guest = guest_user
    guest_person_id = session[:current_person_id] if guest
    existing_account = User.find_by(provider: auth.provider, uid: auth.uid)
    @user = User.from_omniauth(auth, guest, calculator_nationality_record)

    if @user.persisted?
      sign_in @user, :event => :authentication #this will throw if @user is not activated
      if existing_account
        Analytics::GoogleMeasurementProtocol.track(
          'user_login',
          request: request,
          params: {
            category: 'users',
            action: 'login',
            login_method: 'facebook',
            value: 1
          }
        )
      end
      if existing_account
        session[:guest_current_person_id] = guest_person_id if guest_person_id
      else
        session.delete(:guest_user_id)
        session.delete(:guest_current_person_id)
      end
      session.delete(:current_person_id)
      clear_calculator_nationality_session
      set_flash_message(:notice, :success, :kind => "Facebook") if is_navigational_format?
      redirect_to private_visits_path
    elsif @user.errors.of_kind?(:email, :taken)
      session.delete('devise.facebook_data')
      redirect_to new_user_session_path, alert: t('devise.omniauth_callbacks.account_exists')
    else
      # Registration only needs these profile fields, never OAuth credentials.
      session['devise.facebook_data'] = {
        'extra' => { 'raw_info' => auth.info.slice('email', 'first_name', 'last_name').to_h }
      }
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
