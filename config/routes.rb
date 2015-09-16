Rails.application.routes.draw do
#  root 'job_workers#index'
  resources :job_workers, :path => '/'
end
