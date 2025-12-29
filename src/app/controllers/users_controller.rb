class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_action :set_primary_person, only: [:edit, :update]

  def show
  end

  def edit
  end

  def destroy
    @user.destroy
    sign_out
    redirect_to root_path, notice: 'Your account has been successfully deleted.'
  end

  
  def update
    # Update primary person with form data
    respond_to do |format|
      if @primary_person.update(person_params)
        # Keep User fields in sync during transition period
        @user.update_columns(
          first_name: @primary_person.first_name,
          last_name: @primary_person.last_name,
          nationality_id: @primary_person.nationality_id
        )
        
        format.html { redirect_to visits_path, notice: 'Your details were successfully updated.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @primary_person.errors, status: :unprocessable_entity }
      end
    end
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = current_user_or_guest_user
    end

    def set_primary_person
      @primary_person = @user.people.find_by(is_primary: true) || @user.people.first
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def person_params
       params.require(:user).permit(:first_name, :last_name, :nationality_id)
    end
end
