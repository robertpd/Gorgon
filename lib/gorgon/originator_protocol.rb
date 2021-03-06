require 'gorgon/job_definition'

require 'amqp'
require 'uuidtools'

class OriginatorProtocol
  def initialize logger
    @logger = logger
  end

  def connect connection_information, options={}
    @connection = AMQP.connect(connection_information)
    @channel = AMQP::Channel.new(@connection)
    @connection.on_closed { options[:on_closed].call } if options[:on_closed]
    open_queues
  end

  def publish_files files
    @file_queue = @channel.queue("file_queue_" + UUIDTools::UUID.timestamp_create.to_s)

    files.each do |file|
      @channel.default_exchange.publish(file, :routing_key => @file_queue.name)
    end
  end

  def publish_job job_definition
    job_definition.file_queue_name = @file_queue.name
    job_definition.reply_exchange_name = @reply_exchange.name

    @channel.fanout("gorgon.jobs").publish(job_definition.to_json)
  end

  def send_message_to_listeners type, body={}
    # TODO: we probably want to use a different exchange for this type of messages
    message = {:type => type, :reply_exchange_name => @reply_exchange.name, :body => body}
    @channel.fanout("gorgon.jobs").publish(Yajl::Encoder.encode(message))
  end

  def receive_payloads
    @reply_queue.subscribe do |payload|
      yield payload
    end
  end

  def cancel_job
    @file_queue.purge if @file_queue
    @channel.fanout("gorgon.worker_managers").publish(cancel_message)
    @logger.log "Cancel Message sent"
  end

  def disconnect
    cleanup_queues_and_exchange
    @connection.disconnect
  end

  private

  def open_queues
    @reply_queue = @channel.queue("reply_queue_" + UUIDTools::UUID.timestamp_create.to_s)
    @reply_exchange = @channel.direct("reply_exchange_" + UUIDTools::UUID.timestamp_create.to_s)
    @reply_queue.bind(@reply_exchange)
  end

  def cleanup_queues_and_exchange
    @reply_queue.delete if @reply_queue
    @file_queue.delete if @file_queue
    @reply_exchange.delete if @reply_exchange
  end

  def cancel_message
    Yajl::Encoder.encode({:action => "cancel_job"})
  end
end
