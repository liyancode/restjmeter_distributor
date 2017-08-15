# cardiography.rb
# agents info/status collector by heart beat daemon

AgentAddresses=CONFIG["RESTJmeter_Agents"]

# sync lock for sync operation
mutex=Mutex.new

# {"****"=>{:address=>"****",:status=>1,..},}
agents=Hash.new

# global Queue size
global_q_size=0
#============================================
# daemon thread, for heartbeat
Thread.new{
  while true
    mutex.synchronize{
      global_q_size=0
    }
    AgentAddresses.each{|address|
      begin
        client=HTTPClient.new
        size=MultiJson.load(client.get("http://#{address}/rest/hello",{},{}).content)["queue_size"].to_i
        mutex.synchronize{
          agents[address]={:address=>address,:status=>size}
          global_q_size=global_q_size+size
        }
      rescue Exception
        mutex.synchronize{
          agents[address]={:address=>address,:status=>-1}
          global_q_size=0
        }
      end
    }
    sleep(CONFIG["Heartbeat_Interval"]) # heartbeat interval 1 sec
  end
}
#============================================

def choose_best_agent(agents,mutex)
  begin
    address=""
    mutex.synchronize{
      address=agents.first[1][:address]
      status=agents.first[1][:status]
      agents.each{|agent|
        if agent[1][:status]!=-1&&agent[1][:status]<status
          address=agent[1][:address]
          status=agent[1][:status]
        elsif status==-1
          address=agent[1][:address]
          status=agent[1][:status]
        end
      }
    }
    return address
  rescue Exception
    return nil
  end
end

#=================== post new testing ================
post '/rest/jmx' do
  if request.env["HTTP_X_RESTJMETER_TOKEN"]!=CONFIG["X_RESTJmeter_TOKEN"]
    LOGGER.info("Access log. Request with invalid HTTP_X_RESTJMETER_TOKEN:#{request.env["HTTP_X_RESTJMETER_TOKEN"]}")
    status 401
    '{error:"X_RESTJmeter_TOKEN incorrect"}'
  else
    body_str=request.body.string
    LOGGER.info("Access log. Request body:#{body_str}")
    begin
      best_address=choose_best_agent(agents,mutex)
      if agents[best_address][:status]==-1
        status 500
        return '{error:"no available test agent!"}'
      else
        client=HTTPClient.new
        url="http://#{best_address}/rest/jmx"
        response=client.post(url, body_str, {"X_RESTJmeter_TOKEN" => CONFIG["X_RESTJmeter_TOKEN"]})
        status 202
        p test_id=MultiJson.load(response.content)["test_id"]
        MultiJson.dump({:test_id=>test_id})
      end
    rescue Exception=>e
      p e
      p "Incorrect body:#{body_str}"
      LOGGER.error("Access log. Incorrect Request body:#{body_str}")
      LOGGER.error("Access log. Incorrect Request body exception:#{e}")
      status 400
      '{error:"body format incorrect"}'
    end
  end
end

#=================== get testing result================
# GET. return testing status and results to client
get '/rest/result/:testid' do
  LOGGER.info("Access log. GET: #{request}")
  if request.env["HTTP_X_RESTJMETER_TOKEN"]!=CONFIG["X_RESTJmeter_TOKEN"]
    LOGGER.info("Access log. Request with invalid HTTP_X_RESTJMETER_TOKEN:#{request.env["HTTP_X_RESTJMETER_TOKEN"]}")
    status 401
    '{error:"X_RESTJmeter_TOKEN incorrect"}'
  else
    begin
      best_address=choose_best_agent(agents,mutex)
      if agents[best_address][:status]==-1
        status 500
        return '{error:"no available test agent!"}'
      else
        testid=params[:testid]
        client=HTTPClient.new
        extheader = {"X_RESTJmeter_TOKEN" => CONFIG["X_RESTJmeter_TOKEN"]}
        url="http://#{best_address}/rest/result/#{testid}"
        query={}
        response=client.get(url, query, extheader)
        status 200
        return response.content
      end
    rescue Exception=>e
      LOGGER.error(e)
      status 500
    end
  end
end

# get global queue size
get '/rest/queuesize' do
  LOGGER.info("Access log. GET: #{request}")
  if request.env["HTTP_X_RESTJMETER_TOKEN"]!=CONFIG["X_RESTJmeter_TOKEN"]
    LOGGER.info("Access log. Request with invalid HTTP_X_RESTJMETER_TOKEN:#{request.env["HTTP_X_RESTJMETER_TOKEN"]}")
    status 401
    '{error:"X_RESTJmeter_TOKEN incorrect"}'
  else
    begin
      mutex.synchronize{
        status 200
        MultiJson.dump({:queue_size=>global_q_size,:agents=>agents,:server_time=>Time.now.utc})
      }
    rescue Exception=>e
      LOGGER.error(e)
      status 500
    end
  end
end

# 404
not_found do
  'bad path'
end