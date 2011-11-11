require "configuration"
require "yajl"
require "amqp"
require "awesome_print"
require "job_definition"
require "worker"
require "open4"
require "tmpdir"
require "socket"

class Listener
  include Configuration

  def initialize
    @config_filename = Dir.pwd + "gorgon_listener.json"
    @available_worker_slots = configuration[:worker_slots]
  end

  def listen
    AMQP.start(connection_information) do |connection|
      AMQP::Channel.new(connection) do |channel|
        @channel = channel
        channel.queue("", :auto_delete => true, :exclusive => true) do |job_queue, reply|
          @job_queue = job_queue
          exchange = channel.fanout("gorgon.jobs")
          @job_queue.bind(exchange)
          handle_jobs
        end
      end
    end
  end

  def handle_jobs
    @job_queue.subscribe do |json_payload|
      payload = Yajl::Parser.new(:symbolize_keys => true).parse(json_payload)
      @job_definition = JobDefinition.new(payload)
      @reply_exchange = @channel.direct(@job_definition.reply_exchange_name)
      tempdir = Dir.mktmpdir("gorgon")
      Dir.chdir(tempdir)
      system("rsync -r --rsh=ssh #{@job_definition.source_tree_path}/* .")
      fork_workers
    end
  end

  def fork_workers
    configuration[:worker_slots].times do
      @available_worker_slots -= 1
      pid, stdin, stdout, stderr = Open4::popen4 "gorgon work #{@job_definition.file_queue_name} #{@job_definition.reply_exchange_name} '#{@config_filename}'"

      watcher = proc do
        ignore, status = Process.waitpid2 pid
        status
      end

      worker_complete = proc do |status|
        if status.exitstatus != 0
          reply = {:type => :crash,
                   :hostname => Socket.gethostname,
                   :stdout => stdout.read,
                   :stderr => stderr.read}
          @reply_exchange.publish(Yajl::Encoder.encode(reply))
        end
        on_worker_complete
      end

      EventMachine.defer(watcher, worker_complete)
    end
    @job_queue.unsubscribe
  end

  def on_worker_complete
    @available_worker_slots += 1
    if @available_worker_slots == connection_information[:worker_slots]
      handle_jobs
    end
  end

  def connection_information
    configuration[:connection]
  end

  def configuration
    @configuration ||= load_configuration_from_file("gorgon_listener.json")
  end
end
