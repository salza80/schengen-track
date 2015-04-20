class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  helper_method :current_person

  def current_person
    current_user_or_guest_user.people.first
  end


  def current_user_or_guest_user
    current_user || guest_user
  end

  private

  def guest_user
    user = User.find_by_id(session[:guest_user_id])
    unless user
      user = create_guest_user
      session[:guest_user_id] = user.id
    end
    user
  end

  def create_guest_user
    user = User.new
    user.guest = true
    user.email = "guest_#{Time.now.to_i}#{rand(99)}@example.com"
    user.password = 'password'
    user.save(validate: false)
    p = user.people.build(first_name: 'Guest', last_name: 'User')
    p.save(validate: false)
    user
 
  end
end
