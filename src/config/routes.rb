Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

  root 'about#about'

  resources :visits
  resources :visas,  except: [:index, :show]
  resources :days, only:[:index]
  get 'my_details' =>  'users#edit'
  put 'my_details' => 'users#update'
  patch 'my_details' => 'users#update'
  get 'user' => 'users#show'
  get 'about' => 'about#about'
  get '/blog/:slug', to: 'blogs#show', as: :blog
  # get '/blog', to: 'blogs#index', as: :blogs
  get 'about/:nationality' => 'about#about'
  get 'disclaimer'  => 'about#discliamer'
  get 'privacy'  => 'about#privacy'
  get 'migrate'  => 'tasks#migrate'
  get 'create'  => 'tasks#create'
  get 'seed'  => 'tasks#seed'
  get 'update_countries'  => 'tasks#update_countries'
  devise_for :users, controllers: { registrations: "users/registrations", omniauth_callbacks: "users/omniauth_callbacks" }
end
