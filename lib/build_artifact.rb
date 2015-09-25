class BuildArtifact
  def initialize(region, s3_location, filename)
    @region = region
    @s3_location = s3_location
    @filename = filename
  end

  def download
    dir = Dir.mktmpdir("rails-asset-distributor-custom-action")
    file = File.open(File.join(dir, filename), "wb")

    s3.get_object(bucket: s3_location.bucket_name, key: s3_location.object_key) do |chunk|
      file.write(chunk)
    end
    
    file.close
  end

  def unzip
    output = `unzip #{file.path} -d #{dir}/unzipped`
  end
end
