class JobWorkersController < ApplicationController
  def create
    index
  end
  
  def index
    # Elastic Beanstalk workers will provide an SQS message id
    message_id = request.headers['X-Aws-Sqsd-Msgid']
    message_id_2 = request.headers['HTTP_X_Aws_Sqsd_Msgid']
    region = 'us-east-1'

    logger.info "message id #{message_id}"
    logger.info "message id 2 #{message_id_2}"
    logger.info "headers"
    #    logger.info request.headers.inspect

    job_id = nil

    begin
      # NOTE: should the codepipeline object be instantiated each time?  (probably)
      codepipeline = Aws::CodePipeline::Client.new(region: 'us-east-1')

      logger.info "== Poll For Jobs =="
      poll_results = codepipeline.poll_for_jobs(
        action_type_id: {
          category: 'Deploy',
          owner: 'Custom',
          provider: 'Rails-Asset-Distributor',
          version: "1" },
        max_batch_size: 1
      )

      logger.info "Total jobs found #{poll_results.jobs.size}"

      if poll_results.jobs.size > 0
        logger.info "#{message_id}: Processing Job"
        job = poll_results.jobs.first
        job_id = job.id

        logger.info "#{message_id}: Acknowledging Job #{job}"
        logger.info "#{message_id}: Job id #{job.id}"
        logger.info "#{message_id}: Job nonce #{job.nonce}"
        response = codepipeline.acknowledge_job(job_id: job.id, nonce: job.nonce)
        logger.info "#{message_id}: acknowledge job status #{response.status}"

        # do important processing here
        rails_app_meta_data = job.data.input_artifacts.first

        if rails_app_meta_data.empty?
          success = codepipeline.put_job_failure_result(
            job_id: job.id,
            failure_details: {
              type: "ConfigurationError",
              message: "No artifact specified to extract assets from.",
              external_execution_id: '102',  # this should be unique
            }
          )

          render plain: "Rails Artifact not specified", status: 400
          return
        end

        logger.info "#{message_id}: Returning success status"

        s3_location = rails_app_meta_data.location.s3_location
        s3_location.bucket_name
        s3_location.object_key
        filename = rails_app_meta_data.name

        logger.info "#{message_id}: s3 location bucket name #{s3_location.bucket_name}"
        logger.info "#{message_id}: s3 location object key #{s3_location.object_key}"

        s3 = Aws::S3::Client.new(region: region)

        dir = Dir.mktmpdir("precompile-assets")
        file = File.open(File.join(dir, filename), "wb")

        # NOTE - should I be doing something with encryption?
        s3.get_object(bucket: s3_location.bucket_name, key: s3_location.object_key) do |chunk|
          file.write(chunk)
        end

        file.close

        logger.info "write file #{file.path}"
        # Copy to S3
        logger.info "== Unzip #{file.path}"
        output = `unzip #{file.path} -d #{dir}/unzipped`
        logger.info output

        logger.info "== Ensure we have the gems"
        Dir.chdir "#{dir}/unzipped" do
          cmd = "bundle"
          output = `#{cmd}`
          logger.info output
        end

        logger.info "== Precompile the assets"
        Bundler.with_clean_env do
          Dir.chdir "#{dir}/unzipped" do
            output = `RAILS_ENV=production bundle exec rake assets:precompile`
            logger.info output
          end
        end

        logger.info "== Sync to S3"
        asset_bucket = ENV['S3_ASSET_BUCKET'] || "markmans-reinvent-demo-assets"
        logger.info "ENV S3 asset bucket #{asset_bucket}"
        output = `aws s3 sync #{dir}/unzipped/public/assets s3://#{asset_bucket}/assets/`
        logger.info output

        success = codepipeline.put_job_success_result(
          job_id: job.id,
          execution_details: {
            summary: 'Success',
            external_execution_id: '102',  # this should be unique
            percent_complete: 100}
        )

        logger.info "success is #{success} for job id #{job.id}"

        render plain: "Ok", status: 200
      else
        logger.info "#{message_id}: No Jobs"
        render plain: "Ok", status: 200
      end
    rescue Aws::CodePipeline::Errors::ServiceError,
           RuntimeError,
           StandardError => e
      logger.error "#{message_id}: contains an error"
      logger.error e

      if job_id
        success = codepipeline.put_job_failure_result(
          {
            job_id: job_id,
            failure_details: {
              type: "JobFailed",
              message: "error: #{e}",
              external_execution_id: '102'  # this should be unique
            }
          }
        )
        logger.error "#{message_id}: Put Job failure for #{job_id}"
      else
        logger.error "There is need to update job status as no job was acknowledged."
      end

      render plain: e, status: 500
    end
  end
end
