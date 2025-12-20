

class BlogsController < ApplicationController
  def index
    if current_user_or_guest_user.is_guest?
      expires_in 1.month, public: true
    end
  end

  def show
    if current_user_or_guest_user.is_guest?
      expires_in 1.month, public: true
    end
    
    # Set blog-specific meta tags
    set_blog_meta_tags(params[:slug])
    
    render "blogs/#{params[:slug]}", layout: 'application'
  rescue ActionView::MissingTemplate
    render file: 'public/404.html', status: :not_found
  end
  
  private
  
  def set_blog_meta_tags(slug)
    case slug
    when 'extended-schengen-stay'
      @meta_description = I18n.t('blog.extendedTravel.introduction').truncate(160)
      @meta_title = I18n.t('blog.extendedTravel.title')
      @og_type = 'article'
      @og_url = "https://#{request.host_with_port}#{request.path}"
      # Use full URL for og:image (required for Facebook)
      image_path = view_context.asset_path('switzerland.jpg')
      @og_image = "https://#{request.host_with_port}#{image_path}"
      @og_site_name = "Schengen Calculator"
      @article_published_time = "2024-01-15T00:00:00Z"
      @article_modified_time = "2024-01-15T00:00:00Z"
    end
  end
end
