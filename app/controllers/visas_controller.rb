class VisasController < ApplicationController
  before_action :set_visa, only: [:show, :edit, :update, :destroy]

  # GET /visas
  # GET /visas.json
  def index
    @visas = current_person.visas.all
  end

  # GET /visas/1
  # GET /visas/1.json
  def show
  end

  # GET /visas/new
  def new
    @visa = Visa.new
  end

  # GET /visas/1/edit
  def edit
  end

  # POST /visas
  # POST /visas.json
  def create
    @visa = current_person.visas.build(visa_params)
    @visa.visa_type = 'S'
    respond_to do |format|
      if @visa.save
        format.html { redirect_to visits_url, notice: 'Visa was successfully created.' }
        format.json { render :show, status: :created, location: @visa }
      else
        format.html { render :new }
        format.json { render json: @visa.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /visas/1
  # PATCH/PUT /visas/1.json
  def update
    respond_to do |format|
      if @visa.update(visa_params)
        format.html { redirect_to visits_url, notice: 'Visa was successfully updated.' }
        format.json { render :show, status: :ok, location: @visa }
      else
        format.html { render :edit }
        format.json { render json: @visa.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /visas/1
  # DELETE /visas/1.json
  def destroy
    @visa.destroy
    respond_to do |format|
      format.html { redirect_to visits_url, notice: 'Visa was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_visa
      @visa = current_person.visas.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def visa_params
      params.require(:visa).permit(:start_date, :end_date, :no_entries)
    end
end
