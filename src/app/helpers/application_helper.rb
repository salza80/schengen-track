module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.titleize }
  end

  def active_if(options)
    'active' if params.merge(options) == params
  end
end
