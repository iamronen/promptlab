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
        patch :thread_update_steps
        post :thread_insert_bundle
        post :thread_insert_sequence
        post :thread_fork_strand
        post :thread_duplicate_strand_child_sequence
        post :thread_unbundle_pipeline_sequence
        post :thread_dissolve_strand_bundle
        post :thread_merge_adjacent_strand_steps
      end
    end
    resources :bundles, only: %i[edit update create destroy] do
      member do
        post :duplicate
        post :create_pipeline_sequence
      end
    end
  end

  root "projects#index"
end
