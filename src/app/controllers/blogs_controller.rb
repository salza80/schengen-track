

class BlogsController < ApplicationController
  # Blog posts registry - add new posts here (most recent first)
  BLOG_POSTS = [
    {
      slug: 'extended-schengen-stay',
      published_date: Date.new(2024, 1, 15),
      reading_time: 8,
      title_key: 'blog.extendedTravel.title',
      description_key: 'blog.extendedTravel.introduction'
    }
    # Future posts added here, newest first
  ].freeze
  
  def index
    if current_user_or_guest_user.is_guest?
      if Rails.env.development?
        # In development, prevent browser caching to match production behavior
        # (Production: CloudFront's ResponseHeadersPolicy overrides Cache-Control to no-cache)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      else
        # Tell CloudFront to cache for 1 month (only in production)
        expires_in 1.month, public: true
      end
    end
    
    @blog_posts = blog_posts_for_locale
    
    # Redirect to most recent post
    if @blog_posts.any?
      redirect_to blog_path(locale: I18n.locale, slug: @blog_posts.first[:slug])
    else
      render plain: 'No blog posts available', status: :not_found
    end
  end

  def show
    if current_user_or_guest_user.is_guest?
      if Rails.env.development?
        # In development, prevent browser caching to match production behavior
        # (Production: CloudFront's ResponseHeadersPolicy overrides Cache-Control to no-cache)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      else
        # Tell CloudFront to cache for 1 month (only in production)
        expires_in 1.month, public: true
      end
    end
    
    @blog_posts = blog_posts_for_locale
    @current_slug = params[:slug]
    
    # Set blog-specific meta tags
    set_blog_meta_tags(@current_slug)
    
    render "blogs/#{@current_slug}", layout: 'application'
  rescue ActionView::MissingTemplate
    render file: 'public/404.html', status: :not_found
  end
  
  private
  
  def blog_posts_for_locale
    BLOG_POSTS.map do |post|
      post.merge(
        title: I18n.t(post[:title_key]),
        description: I18n.t(post[:description_key]).truncate(160)
      )
    end
  end
  
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
      @og_site_name = I18n.t('common.schengen_calculator')
      @article_published_time = "2024-01-15T00:00:00Z"
      @article_modified_time = "2024-01-15T00:00:00Z"
    end
  end
end
