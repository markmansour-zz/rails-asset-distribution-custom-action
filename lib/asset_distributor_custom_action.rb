class AssetDistributorCustomAction
  CATEGORY       = 'Deploy'
  OWNER          = 'Custom'
  PROVIDER       = 'Rails-Asset-Distributor'
  VERSION        = '1'
  MAX_BATCH_SIZE = 1

  attr_reader :region, :error
  attr_reader :poll_results, :job  # for debugging

  def initialize(region, asset_bucket)
    @region = region
    @asset_bucket = asset_bucket
    @codepipeline = Aws::CodePipeline::Client.new(region: region)
  end

  def poll_for_jobs
    @poll_results = @codepipeline.poll_for_jobs({
        action_type_id: {
          category: CATEGORY,
          owner: OWNER,
          provider: PROVIDER,
          version: VERSION
        },
        max_batch_size: MAX_BATCH_SIZE
      })
    
    if has_new_job?
      @job = AssetDistributorJob.new(@poll_results.jobs.first)
      @meta_data = @job.meta_data    
    end
  end

  def process_job
    return no_job_status if ! has_new_job?

    begin
      acknowledge_job

      return put_configuration_failure_result if @job.build_artifact_missing?

      distributor = distribute_rails_assets_to_s3

      if distributor.sync_success?
        put_success_result
      else
        put_s3_sync_failure_result(distributor.sync_output)
      end
    rescue Aws::CodePipeline::Errors::ServiceError, RuntimeError, StandardError => e
      put_job_failed_unexpected_result(e) if @job.acknowledged?
    end
  end

  private

  def has_new_job?
    @poll_results && @poll_results.jobs.size > 0
  end

  def no_job_status
    CustomActionStatus.new(false, nil, "No Jobs", true)
  end

  def acknowledge_job
    @response = @codepipeline.acknowledge_job(job_id: @job.id, nonce: @job.nonce)
  end

  def put_success_result
    @codepipeline.put_job_success_result(
      job_id: @job.id,
      execution_details: {
        summary: 'Success',
        external_execution_id: @job.token,
        percent_complete: 100}
      )

    CustomActionStatus.new(true)
  end

  def distribute_rails_assets_to_s3
    distributor = AssetDistributor.new(@region,
      @meta_data.location.s3_location,
      @meta_data.name,
      @asset_bucket)

    distributor.download
    distributor.unzip
    distributor.sync_unzipped_assets

    distributor
  end

  def put_configuration_failure_result
    put_failure("ConfigurationError", "No artifact specified to extract assets from.")
  end

  def put_job_failed_result(e)
    put_failure("JobFailed", nil)
  end

  def put_job_failed_unexpected_result(e)
    put_failure("JobFailed", e, nil, false)
  end

  def put_s3_sync_failure_result(message)
    put_failure("JobFailed", nil, "error: S3 Sync #{message}")
  end

  def put_failure(type, error = nil, message = nil, expected = true)
    display_message = message
    display_message = "Error:  #{error}" if error && display_message.nil?

    @codepipeline.put_job_failure_result({ job_id: @job.id,
        failure_details: {
          type: type,
          message: display_message,
          external_execution_id: @token
        }
      })

    CustomActionStatus.new(false, error, message, expected)
  end
end
