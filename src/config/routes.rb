Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  scope "(:locale)", locale: /#{I18n.available_locales.join("|")}/ do
    root 'about#about'

    resources :visits do
      collection do
        get 'for_date' # Get visits for a specific date
        get 'max_stay_info' # Get max stay info for entry date
      end
    end
    resources :visas, except: [:index, :show]
    resources :days, only: [:index]
    resources :people do
      member do
        post :set_current
        post :make_primary
      end
    end
    
    get 'my_details' => 'users#edit'
    patch 'my_details' => 'users#update'
    delete 'my_details' => 'users#destroy', as: 'delete_account'
    get 'user' => 'users#show'
    get 'about' => 'about#about'
    get 'blog' => 'blogs#index', as: :blog_index
    get 'blog/:slug' => 'blogs#show', as: :blog
    get 'about/:nationality' => 'about#about'
    get 'disclaimer' => 'about#disclaimer'
    get 'privacy' => 'about#privacy'
    get 'datadeletion' => 'about#datadeletion'
    
    get 'unlock_migrations' => 'tasks#unlock_migrations'
    get 'migrate' => 'tasks#migrate'
    get 'create' => 'tasks#create'
    get 'seed' => 'tasks#seed'
    get 'update_countries' => 'tasks#update_countries'
    get 'guest_cleanup' => 'tasks#guest_cleanup'

    devise_for :users, skip: :omniauth_callbacks, controllers: {
      registrations: 'users/registrations',
      sessions: 'users/sessions'
    }

  end
  devise_for :users, only: :omniauth_callbacks, controllers: {omniauth_callbacks: 'users/omniauth_callbacks'}
end
