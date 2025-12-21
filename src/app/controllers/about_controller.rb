class AboutController < ApplicationController

  # GET /about/
  # GET /about/:nationaity
  def about
    if current_user_or_guest_user.is_guest?
      expires_in 1.month, public: true
    end
    
    # Set SEO meta tags for about page
    set_about_meta_tags
    
    @country = nil
    return if params[:nationality].nil?
    nationality = params[:nationality]
    nationality.gsub("_", " ")
    @country = Country.find_by_nationality(nationality)
               .outside_schengen.first
    fail ActionController::RoutingError, 'Page Not Found' if @country.nil?
  end

  # GET /disclaimer/
  def disclaimer
    set_page_meta_tags('Disclaimer')
  end
  
  # GET /privacy/
  def privacy
    set_page_meta_tags('Privacy Policy')
  end
  
  private
  
  def set_about_meta_tags
    @meta_title = I18n.t('default_title')
    @meta_description = I18n.t('default_description')
    @og_type = 'website'
    @og_url = "https://#{request.host_with_port}#{request.path}"
    # Use schengen map image for about page
    image_path = view_context.asset_path('schengen_area_eu_countries.webp')
    @og_image = "https://#{request.host_with_port}#{image_path}"
    @og_site_name = "Schengen Calculator"
  end
  
  def set_page_meta_tags(page_name)
    @meta_title = "#{page_name} - Schengen Calculator"
    @meta_description = I18n.t('default_description')
    @og_type = 'website'
    @og_url = "https://#{request.host_with_port}#{request.path}"
    image_path = view_context.asset_path('schengen_area_eu_countries.webp')
    @og_image = "https://#{request.host_with_port}#{image_path}"
    @og_site_name = "Schengen Calculator"
  end
end
