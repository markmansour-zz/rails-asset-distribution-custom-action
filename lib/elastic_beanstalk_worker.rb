class ElasticBeanstalkWorker
  def initialize(request)
    @request = request
  end

  def message_id
    request.headers['X-Aws-Sqsd-Msgid']
  end
end
