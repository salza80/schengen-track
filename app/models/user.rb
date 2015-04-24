class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  has_many :people, dependent: :destroy
  accepts_nested_attributes_for :people
  
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable


  def is_guest?
    self.guest
  end
end
