class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_action :set_primary_person, only: [:edit, :update]

  def show
  end

  def edit
  end

  def update
    respond_to do |format|
      if @user.update(user_params)
        # Sync User fields to primary person to keep them in sync
        @primary_person.update_columns(
          first_name: @user.first_name,
          last_name: @user.last_name,
          nationality_id: @user.nationality_id
        )
        
        format.html { redirect_to visits_path, notice: 'Your details were successfully updated.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    # Manually destroy all people (and their visits/visas via dependent: :delete_all) 
    # to avoid the prevent_last_person_deletion callback
    @user.people.each do |person|
      person.visits.delete_all
      person.visas.delete_all
    end
    @user.people.delete_all
    @user.destroy
    
    sign_out
    redirect_to root_path, notice: 'Your account has been successfully deleted.'
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
    def user_params
      params.require(:user).permit(:first_name, :last_name, :nationality_id)
    end
end
