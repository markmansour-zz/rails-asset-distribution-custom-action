Rails.application.routes.draw do
  get 'job_workers/index'

  # root 'welcome#index'
  resources :job_workers
end
