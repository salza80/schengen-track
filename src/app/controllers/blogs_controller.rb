

class BlogsController < ApplicationController
  def index
    if current_user_or_guest_user.is_guest?
      expires_in 1.month, public: true
    end
    puts 'here'
    # @country = Country.find_by_nationality(params[:nationality])
    #            .outside_schengen.first
  end

  def show
    if current_user_or_guest_user.is_guest?
      expires_in 1.month, public: true
    end
    puts 'here'
    # @country = Country.find_by_nationality(params[:nationality])
    #            .outside_schengen.first
    puts "blogs/#{params[:slug]}"
    render "blogs/#{params[:slug]}", layout: 'application'
  rescue ActionView::MissingTemplate
    render file: 'public/404.html', status: :not_found
  end
end
