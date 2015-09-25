class AssetDistributorCustomAction
  CATEGORY = 'Deploy'
  OWNER = 'Custom'
  PROVIDER = 'Rails-Asset-Distributor'
  VERSION = '1'
  MAX_BATCH_SIZE = 1

  attr_reader :region
  attr_reader :poll_results, :job  # for debugging

  def initialize(region)
    @region = region
    @codepipeline = Aws::CodePipeline::Client.new(region: region)
  end

  def poll_for_jobs
    @poll_results = @codepipeline.poll_for_jobs(
                                                {
                                                  action_type_id: {
                                                    category: CATEGORY,
                                                    owner: OWNER,
                                                    provider: PROVIDER,
                                                    version: VERSION
                                                  },
                                                  max_batch_size: MAX_BATCH_SIZE
                                                }
                                                )
  end

  def has_new_job?
    @poll_results && @poll_results.jobs.size > 0
  end

  def process_job
    return nil if ! has_new_job?

    begin
      @job = AssetDistributorJob.new(@poll_results.jobs.first)

      meta_data = @job.meta_data
      acknowledge_job

      return put_configuration_failure_result if @job.build_artifact_missing?

      s3_location = meta_data.location.s3_location
      filename = meta_data.name

      s3 = Aws::S3::Client.new(region: @region)

      dir = Dir.mktmpdir("rails-asset-distributor-custom-action")
      file = File.open(File.join(dir, filename), "wb")

      # Copy pipeline artifact from S3 to local disk
      # NOTE - should I be doing something with encryption?
      s3.get_object(bucket: s3_location.bucket_name, key: s3_location.object_key) do |chunk|
        file.write(chunk)
      end

      file.close

      output = `unzip #{file.path} -d #{dir}/unzipped`
      asset_bucket = ENV['S3_ASSET_BUCKET'] || "markmans-reinvent-demo-assets"
      output = `aws s3 sync --delete #{dir}/unzipped/public/assets s3://#{asset_bucket}/assets/`

      if $?.success?   # checks the return code from the backtick shell command
        put_success_result
      else
        put_s3_sync_failure_result(output)
      end
    rescue Aws::CodePipeline::Errors::ServiceError, RuntimeError, StandardError => e
      put_job_failed_unexpected_result(e) if @job.acknowledged?
    end
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

  def put_configuration_failure_result
    put_failure("ConfigurationError", "No artifact specified to extract assets from.")
  end

  def put_job_failed_result(e)
    put_failure("JobFailed", "error: #{e}")
  end

  def put_job_failed_unexpected_result(e)
    put_failure("JobFailed", "error: #{e}", false)
  end

  def put_s3_sync_failure_result(message)
    put_failure("JobFailed", "error: S3 Sync #{message}")
  end

  def put_failure(type, message, expected = true)
    @codepipeline.put_job_failure_result({ job_id: @job.id,
                                           failure_details: {
                                             type: type,
                                             message: message,
                                             external_execution_id: @token
                                           }
                                         })

    CustomActionStatus.new(false, message, expected)
  end
end
