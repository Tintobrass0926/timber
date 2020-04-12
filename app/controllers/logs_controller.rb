class LogsController < ApplicationController
  include QueryParser
  before_action :set_aggregations, only: :index

  def index
    search_params = parse_query(params)
    puts JSON.pretty_generate(search_params) if ENV['FULL_LOGGING']
    @logs = LOG_REPO.search(search_params)
  end

  def create
    case params[:log_type]
    when "overmind"
      parse_overmind
    end

    head :no_content
  end

  private

  def parse_overmind
    original_log = request.body.read
    puts original_log if ENV['FULL_LOGGING']

    # Parse the log
    log = original_log.gsub(/\e\]0;/, '')

    # Find the source
    preamble, log = log.include?("\e[1m") ? log.split("\e[1m", 2) : log.split("\e[0m | ", 2)
    source, _ = Strings::ANSI.sanitize(preamble).split(" | ")
  
    # Save the log
    if source != "echo" && log&.strip&.present?
      tags = Strings::ANSI.sanitize(log).scan(/\[(\w+)\]/).map(&:first)
      new_log = GenericLog.new(
        'source' => source.strip,
        'log' =>  log.gsub(/(\[\w+\])/, '').strip,
        'application' => params[:application].strip,
        'tags' => tags,
      )
      LOG_REPO.save(new_log)
    end
  end

  def set_aggregations
    @aggregations ||= begin
      query = {
        size: 0,
        aggs: {
          applications: { terms: { field: "application",  size: 500 } },
          sources: { terms: { field: "source",  size: 500 } }
        }
      }
      response = LOG_REPO.search(query)
      aggregations = response.raw_response["aggregations"]
      aggregations.map { |k, v| [k, v["buckets"].map { |b| b["key"] }.sort] }.to_h
    end
  end
end
