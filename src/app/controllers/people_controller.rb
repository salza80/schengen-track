class PeopleController < ApplicationController
  before_action :set_person, only: [:edit, :update, :destroy, :set_current, :make_primary]

  def index
    @people = current_user_or_guest_user.people.ordered
  end

  def new
    @person = current_user_or_guest_user.people.new
    # Pre-fill nationality from primary person
    primary_person = current_user_or_guest_user.people.find_by(is_primary: true)
    @person.nationality_id = primary_person&.nationality_id
  end

  def create
    @person = current_user_or_guest_user.people.new(person_params)
    
    if @person.save
      # Track analytics when users create additional people (not primary)
      if current_user_or_guest_user.people.count > 1
        tracker = Staccato.tracker('UA-67599800-1', current_user_or_guest_user.id)
        tracker.event(category: 'people', action: 'create_additional_person', label: 'multi_person_tracking', value: 1)
      end
      
      redirect_to people_path, notice: 'Person was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @person.update(person_params)
      redirect_to people_path, notice: 'Person was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @person.is_primary
      redirect_to people_path, alert: 'Cannot delete the primary person. Please make another person primary first.'
    elsif @person.destroy
      redirect_to people_path, notice: 'Person was successfully deleted.'
    else
      redirect_to people_path, alert: @person.errors.full_messages.join(', ')
    end
  end

  def set_current
    session[:current_person_id] = @person.id
    redirect_back_or_to root_path, notice: "Switched to #{@person.full_name}"
  end

  def make_primary
    # Remove primary status from all user's people
    current_user_or_guest_user.people.update_all(is_primary: false)
    
    # Make this person primary
    @person.update(is_primary: true)
    
    redirect_back_or_to people_path, notice: "#{@person.full_name} is now your primary person"
  end

  private

  def set_person
    @person = current_user_or_guest_user.people.find(params[:id])
  end

  def person_params
    params.require(:person).permit(:first_name, :last_name, :nationality_id)
  end
end
