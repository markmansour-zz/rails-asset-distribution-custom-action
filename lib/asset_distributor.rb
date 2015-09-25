class AssetDistributor
  attr_reader :sync_output

  def initialize(region, s3_build_artifact_location, build_artifact_filename, distribution_s3_location)
    @region = region
    @s3_build_artifact_location = s3_build_artifact_location
    @build_artifact_filename = build_artifact_filename
    @distribution_s3_location = distribution_s3_location
    @build_artifact_path
  end

  def download
    s3 = Aws::S3::Client.new(region: @region)

    @tmpdir = Dir.mktmpdir("rails-asset-distributor-custom-action")

    File.open(File.join(@tmpdir, @build_artifact_filename), "wb") do |file|
      # Copy pipeline artifact from S3 to local disk
      # NOTE - should I be doing something with encryption?
      s3.get_object(bucket: @s3_build_artifact_location.bucket_name, 
                    key: @s3_build_artifact_location.object_key) do |chunk|
        file.write(chunk)
        @build_artifact_path = file.path
      end
    end
  end

  def unzip
    output = `unzip #{@build_artifact_path} -d #{@tmpdir}/unzipped`
  end

  def sync_unzipped_assets
    @sync_output = `aws s3 sync --delete #{@tmpdir}/unzipped/public/assets s3://#{@distribution_s3_location}/assets/`
    @sync_status = $?  # the return code from the backtick shell command
  end

  def sync_success?
    @sync_status.success?
  end
end
