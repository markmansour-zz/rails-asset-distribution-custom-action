class AssetDistributorJob
  extend Forwardable

#  attr_reader :id, :token
#  attr_reader :meta_data, :job # for debugging

  attr_reader :id, :token
  attr_reader :meta_data

  def_delegators :@job, :id, :nonce

  def initialize(job)
    @job = job
    @id = job.id
    @nonce = job.nonce
    generate_token
    extract_meta_data
  end

  def build_artifact_missing?
    @meta_data.empty?
  end

  def acknowledged?
    ! id.nil?
  end

  private

  def generate_token
    @token = SecureRandom.uuid
  end

  def extract_meta_data
    @meta_data = @job.data.input_artifacts.first
  end
end
