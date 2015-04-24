class Users::RegistrationsController < Devise::RegistrationsController
  before_filter :configure_sign_up_params, only: [:create]
  before_filter :configure_account_update_params, only: [:update]

  # GET /resource/sign_up
  def new
    @user= User.new
    @user.people << Person.new

  end

  # POST /resource
  def create
    @user = User.create(sign_up_params)
    @guest_user = current_user_or_guest_user
    @user.people.first.copy_from(@guest_user.people.first)
    if @user.save    
      # n = Country.find_by(country_code: 'AU')
      # @p = Person.new(first_name: 'New', last_name: 'User', nationality: n)
      # @p.copy_from(@guest_user.people.first)
      # @p.user = @user
      # @p.save!

      sign_up('user', @user)
      redirect_to root_path
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

  # You can put the params you want to permit in the empty array.
  def configure_sign_up_params
    devise_parameter_sanitizer.for(:sign_up) << [people_attributes: [ :first_name, :last_name, :nationality_id ] ]
  end

  # You can put the params you want to permit in the empty array.
  def configure_account_update_params
    devise_parameter_sanitizer.for(:account_update) << :attribute
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
