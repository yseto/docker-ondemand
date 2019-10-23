class Dondemand
  attr_accessor :container
  attr_accessor :test_endpoint

  def initialize(container, test_endpoint)
    @container = container
    @test_endpoint = test_endpoint
  end

  def call(env)
    endpoint = "dondemand:5000"
    begin
      req = http_request("http://" + endpoint + "/" + @container + "/-/" + @test_endpoint)
    rescue => e
      return [500, [], ["Internal Server Error"]]
    end

    status, headers, body = req.join
    if status < 400
      return [399, {}, []]
    end
    [500, [], ["Internal Server Error"]]
  end
end
