class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  belongs_to :nationality, class_name: 'Country'
  has_many :people, dependent: :delete_all
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

  # Move every traveler from an existing guest session into this account. Keeping
  # them as separate, non-primary people preserves all records without creating
  # date conflicts with travelers that are already stored on the account.
  def transfer_guest_people!(guest_user, current_person_id: nil)
    return unless guest_user&.is_guest? && guest_user.id != id

    transferred_person_id = nil

    User.transaction do
      lock!
      guest_user.lock!
      ensure_primary_person

      guest_people = guest_user.people.to_a
      selected_person = guest_people.find { |person| person.id == current_person_id } ||
                        guest_people.find(&:is_primary?) || guest_people.first
      transferred_person_id = selected_person&.id

      guest_user.people.update_all(
        user_id: id,
        is_primary: false,
        updated_at: Time.current
      )
      guest_user.delete
    end

    people.reset
    people.find_by(id: transferred_person_id)
  end

  def self.from_omniauth(auth, guest_user, fallback_nationality = nil)
    puts auth
    user = User.find_by(provider: auth.provider, uid: auth.uid)
    return user if user
    user = register_oauth_with_matching_email(auth)
    unless user
      guest_profile = guest_user&.people&.find_by(is_primary: true) || guest_user&.people&.first || guest_user
      user = User.create do |user|
        user.provider = auth.provider
        user.uid = auth.uid
        user.email = auth.info.email
        user.password = Devise.friendly_token[0, 20]
        user.first_name = guest_profile&.first_name || auth.info.first_name || "New"
        user.last_name = guest_profile&.last_name || auth.info.last_name || "User"
        user.nationality = guest_profile&.nationality || fallback_nationality || Country.find_by(country_code: 'US')
      end
      user.copy_from(guest_user)
      if data = auth['extra']['raw_info']
        user.first_name =  data['first_name']
        user.last_name = data['last_name'] 
      end
      user.save
      user.reload
      Analytics::GoogleMeasurementProtocol.track(
        'user_signup',
        client_id: Analytics::GoogleMeasurementProtocol.client_id_from_key("user:#{user.id}"),
        params: {
          category: 'users',
          action: 'signup',
          label: 'facebook',
          signup_method: 'facebook',
          value: 1
        }
      )
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

  # Ensure user has at least one person record
  # Creates a primary person from user data if none exist
  def ensure_primary_person
    return if people.exists?
    
    Rails.logger.warn("User #{id} has no people - creating primary person from user data")
    
    people.create!(
      first_name: first_name.presence || 'User',
      last_name: last_name,
      nationality_id: nationality_id,
      is_primary: true
    )
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
