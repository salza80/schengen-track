class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  has_many :people, dependent: :destroy
  accepts_nested_attributes_for :people
  
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, 
         :omniauthable, :omniauth_providers => [:facebook]

  def self.from_omniauth(auth)
     register_oauth_with_matching_email(auth)
     user = where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
        user.provider = auth.provider
        user.uid = auth.uid
        user.email = auth.info.email
        user.password = Devise.friendly_token[0, 20]
      end
  end

  def self.register_oauth_with_matching_email(auth)
    user = where("provider is null and uid is null and email = :email",email: auth.info.email).first
    if user
      user.uid = auth.uid
      user.provider = auth.provider
      user.save
    end
  end

  def self.new_with_session(params, session)
    super.tap do |user|
      if data = session['devise.facebook_data'] && session['devise.facebook_data']['extra']['raw_info']
        user.email = data['email'] if user.email.blank?
        if user.people.empty?
          p = Person.new
          user.people << p
        else
          p = user.people.first
        end
        p.first_name = data['first_name'] if p.first_name.blank?
        p.last_name = data['last_name'] if p.last_name.blank?
         # p.last_name = Geocoder.search(data['location']['name']).first.country
      end
    end
  end

  def is_guest?
    self.guest
  end
end
