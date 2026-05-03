Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :projects, only: %i[index update] do
    member do
      get :open
      get :settings
    end
    resources :sequences, only: %i[edit update create destroy] do
      member do
        post :duplicate
        post :add_to_terms
        post :remove_from_terms
      end
    end
    resources :transformations, only: %i[edit update create destroy] do
      member do
        post :duplicate
        post :create_pipeline_sequence
      end
    end
  end

  root "projects#index"
end
