class JobWorkersController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    render plain: "Called as a GET.  This endpoint responds to POST", status: 200
  end
  
  def create
    logger.info "== Poll For Jobs =="

    region = ENV['AWS_DEFAULT_REGION']
    asset_bucket = ENV['S3_ASSET_BUCKET']
    message_id = ElasticBeanstalkWorker.new(request).message_id

    custom_action = AssetDistributorCustomAction.new(region, asset_bucket)

    custom_action.poll_for_jobs

    if ! custom_action.has_new_job?
      logger.info "#{message_id}: No Jobs"
      return render json: { status:"ok" }, status: 200
    end

    status = custom_action.process_job

    logger.info "#{message_id}: Processing Job #{custom_action.job.id}"

    if status.ok?
      logger.info "#{message_id}: Successfully processed custom action"
      render json: status.to_h, status: 200
    else
      logger.error "#{message_id}: Unsuccessfully processed custom action"
      logger.error "#{message_id}: #{status.message}"
      logger.error "#{message_id}: #{status.error}"
      render json: status.to_h, status: status.expected? ? 400 : 500
    end
  end
end
