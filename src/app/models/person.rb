class Person < ApplicationRecord
  belongs_to :user
  belongs_to :nationality, class_name: 'Country', foreign_key: :nationality_id, optional: true
  has_many :visits, dependent: :delete_all
  has_many :visas, dependent: :delete_all

  validates :first_name, presence: true
  validates :user_id, presence: true

  scope :ordered, -> { order(is_primary: :desc).order(Arel.sql("LOWER(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''))")) }

  before_destroy :prevent_primary_person_deletion
  before_destroy :prevent_last_person_deletion
  before_save :ensure_single_primary_for_user, if: :becoming_primary?

  def full_name
    [first_name, last_name].compact.join(' ')
  end

  def nationality_with_default
    nationality || Country.find_by(country_code: "US")
  end

  def visa_required?
    nationality_with_default.visa_required == 'V'
  end

  private

  def becoming_primary?
    will_save_change_to_is_primary? && is_primary? && user.present?
  end

  def ensure_single_primary_for_user
    user.people.where.not(id: id).where(is_primary: true).update_all(is_primary: false)
  end

  def prevent_primary_person_deletion
    if is_primary
      errors.add(:base, "Cannot delete the primary person. Please make another person primary first.")
      throw(:abort)
    end
  end

  def prevent_last_person_deletion
    if user.people.count == 1
      errors.add(:base, "Cannot delete your only person")
      throw(:abort)
    end
  end
end
