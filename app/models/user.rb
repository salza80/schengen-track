class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  has_many :people, dependent: :destroy
  accepts_nested_attributes_for :people
  
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, 
         :omniauthable, :omniauth_providers => [:facebook]

  def self.from_omniauth(auth, guest_user)
    user = User.find_by(provider: auth.provider, uid: auth.uid)
    return user if user
    user = register_oauth_with_matching_email(auth)
    unless user 
      user = User.create do |user|
        user.provider = auth.provider
        user.uid = auth.uid
        user.email = auth.info.email
        user.password = Devise.friendly_token[0, 20]
      end
      p = Person.copy_from(guest_user.people.first)
      if data =auth['extra']['raw_info']
        p.first_name =  data['first_name']
        p.last_name = data['last_name'] 
      end
      user.people << p
      user.save
      tracker = Staccato.tracker('UA-67599800-1', user.id)
      tracker.event(category: 'users', action: 'signup', label: 'facebook', value: 1)
    end
    user
  end

  def self.register_oauth_with_matching_email(auth)
    user = find_by(email: auth.info.email)
    return nil unless user
    user.uid = auth.uid
    user.provider = auth.provider
    user.save
    user
  end

  def self.new_with_session(params, session)
    super.tap do |user|
      if user.people.empty? 
        p = Person.new
        user.people << p
        else
          p = user.people.first
      end
      if data = session['devise.facebook_data'] && session['devise.facebook_data']['extra']['raw_info']
        user.email = data['email'] if user.email.blank?
        p.first_name = data['first_name'] if p.first_name.blank?
        p.last_name = data['last_name'] if p.last_name.blank?
        #location must requested from facebook, and they must review the app. Implement later.
        # puts session['devise.facebook_data']
        # puts session['devise.facebook_data']['extra']['raw_info']
        #p.nationality = Geocoder.search(data['location'].first.country
      end
    end
  end

  def is_guest?
    self.guest
  end
end
