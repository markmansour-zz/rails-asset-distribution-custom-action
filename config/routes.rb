Rails.application.routes.draw do
  # get 'job_workers/index'

  root 'job_workers#index'
  resources :job_workers
end
