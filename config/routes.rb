Rails.application.routes.draw do
  resources :job_workers

  get '/', to: 'job_workers#index'
  post '/', to: 'job_workers#create'
end
