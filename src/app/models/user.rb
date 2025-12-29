class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  belongs_to :nationality, class_name: 'Country'
  has_many :people, dependent: :destroy
  validates :first_name, :last_name, :nationality, presence: true

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, 
         :omniauthable, :omniauth_providers => [:facebook]

  after_create :create_primary_person

  def full_name
    [first_name, last_name].join(' ').strip
  end

  def nationality
    super || Country.find_by(country_code: "US")
  end

  def visa_required?
    nationality.visa_required == 'V'
  end

  # used on omniauth signup
  def copy_from(user)
    # Copy visits and visas from the guest user's primary person to this user's primary person
    return unless user
    
    # Get the guest user's primary person (or first person)
    guest_person = user.people.where(is_primary: true).first || user.people.first
    return unless guest_person
    
    # Get this user's primary person
    my_person = self.people.where(is_primary: true).first || self.people.first
    return unless my_person
    
    # Copy visits
    guest_person.visits.each do |v|
      my_person.visits << v.dup
    end
    
    # Copy visas
    guest_person.visas.each do |v|
      my_person.visas << v.dup
    end
  end

  def self.from_omniauth(auth, guest_user)
    puts auth
    user = User.find_by(provider: auth.provider, uid: auth.uid)
    return user if user
    user = register_oauth_with_matching_email(auth)
    unless user 
      user = User.create do |user|
        user.provider = auth.provider
        user.uid = auth.uid
        user.email = auth.info.email
        user.password = Devise.friendly_token[0, 20]
        user.first_name = guest_user.first_name || "New"
        user.last_name = guest_user.last_name || "User"
        user.nationality = guest_user.nationality
      end
      guest_user.visits.each do |v|
        user.visits << v.dup
      end
      if data = auth['extra']['raw_info']
        user.first_name =  data['first_name']
        user.last_name = data['last_name'] 
      end
      user.save
      user.reload
      tracker = Staccato.tracker('UA-67599800-1', user.id)
      tracker.event(category: 'users', action: 'signup', label: 'facebook', value: 1)
    end
    user
  end

  def self.register_oauth_with_matching_email(auth)
    return nil unless auth.info.email
    user = find_by(email: auth.info.email)
    return nil unless user
    user.uid = auth.uid
    user.provider = auth.provider
    user.save
    user
  end

  def self.new_with_session(params, session)
    super.tap do |user|
      
      if data = session['devise.facebook_data'] && session['devise.facebook_data']['extra']['raw_info']
        user.email = data['email'] if user.email.blank?
        user.first_name = data['first_name'] if user.first_name.blank?
        user.last_name = data['last_name'] if user.last_name.blank?
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

  private

  def create_primary_person
    people.create!(
      first_name: first_name,
      last_name: last_name,
      nationality_id: nationality_id,
      is_primary: true
    )
  end
end
