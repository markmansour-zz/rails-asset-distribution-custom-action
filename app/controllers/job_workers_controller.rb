class JobWorkersController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    render plain: "Called as a GET.  This endpoint responds to POST", status: 200
  end

  # Handle HTTP POST requests triggered by EB
  def create
    logger.info "== Check for new work =="

    region = ENV['AWS_DEFAULT_REGION']
    asset_bucket = ENV['S3_ASSET_BUCKET']
    message_id = ElasticBeanstalkWorker.new(request).message_id

    custom_action = AssetDistributorCustomAction.new(region, asset_bucket)

    custom_action.poll_for_jobs
    status = custom_action.process_job

    if status.ok?
      logger.info status.message || "#{message_id}: Successfully processed custom action"
      render json: status.to_h, status: 200
    else
      logger.error "#{message_id}: Unsuccessfully processed custom action"
      logger.error "#{message_id}: #{status.message}"
      logger.error "#{message_id}: #{status.error}"
      render json: status.to_h, status: status.expected? ? 400 : 500
    end
  end
end
