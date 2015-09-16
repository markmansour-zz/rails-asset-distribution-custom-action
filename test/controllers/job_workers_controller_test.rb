require 'test_helper'

class JobWorkersControllerTest < ActionController::TestCase
  test "GET /" do
    assert_recognizes({ controller: 'job_workers', action: 'index' }, { path: '/', method: :get })
  end
  
  test "POST /" do
    assert_recognizes({ controller: 'job_workers', action: 'create' }, { path: '/', method: :post })
  end
end
