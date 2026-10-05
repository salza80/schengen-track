class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  # GET /resource/sign_up
  def new
    @user = User.new_with_session({}, session)
    prefill_registration_from_guest(@user)
    @user.nationality = calculator_nationality if @user.nationality_id.blank?
  end

  # POST /resource
  def create
    @guest_user = current_user_or_guest_user
    attributes = sign_up_params.to_h
    attributes['nationality_id'] = registration_nationality_id if attributes['nationality_id'].blank?
    @user = User.new(attributes)
    if @user.save
      @user.copy_from(@guest_user)
      sign_up('user', @user)
      session.delete(:guest_user_id)
      session.delete(:current_person_id)
      session.delete(:calculator_nationality_id)
      Analytics::GoogleMeasurementProtocol.track(
        'user_signup',
        request: request,
        params: {
          category: 'users',
          action: 'signup',
          label: 'email',
          signup_method: 'email',
          value: 1
        }
      )
      redirect_to visits_path
    else
      render :new
    end
  end

  # GET /resource/edit
  def edit
    super
  end

  # PUT /resource
  def update
    super
  end

  # DELETE /resource
  def destroy
    super
  end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  def cancel
    super
  end

  protected

  def prefill_registration_from_guest(user)
    profile = guest_registration_profile
    return unless profile

    user.first_name = profile.first_name if user.first_name.blank?
    user.last_name = profile.last_name if user.last_name.blank?
    user.nationality_id = profile.nationality_id if user.nationality_id.blank?
  end

  def registration_nationality_id
    guest_registration_profile&.nationality_id || calculator_nationality.id
  end

  def guest_registration_profile
    guest = current_user_or_guest_user
    return unless guest&.is_guest?

    guest.people.find_by(is_primary: true) || guest.people.first || guest
  end

  # You can put the params you want to permit in the empty array.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :nationality_id ])
  end

  # You can put the params you want to permit in the empty array.
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  end

  # The path used after sign up.
  def after_sign_up_path_for(resource)
    super(resource)
  end

  # The path used after sign up for inactive accounts.
  def after_inactive_sign_up_path_for(resource)
    super(resource)
  end
end
