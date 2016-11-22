require "fileutils"
require "delayed_job"
require "itunes/store/transporter"
require "itunes/store/transporter/errors"

class TransporterJob < ActiveRecord::Base
  STATES = [:queued, :running, :success, :failure]
  STATES.each do |s|
    define_method("#{s}!") { update_attribute(:state, s) }
    define_method("#{s}?") { state == s }
  end

  PRIORITY = Hash.new(0).merge!(:high => -1, :normal => 0, :low => 1)

  # TODO: params in controller
  #attr_protected :state, :target, :job_id

  serialize :result
  serialize :options, Hash
  serialize :exceptions

  validates :account_id, :presence => true

  belongs_to :account

  before_save :typecast_options, :set_target

  after_create  :enqueue_delayed_job
  after_destroy :dequeue_delayed_job, :remove_log

  scope :completed, lambda { where(:state => [:success, :failure]) }

  def self.search(params)
    criteria = build_search_query(params)

    column = order_by_column(params[:order])
    q = where(criteria).order(column)
    q = q.joins(:account) if column.start_with?("account")

    q
  end

  def command
    self.class.to_s.split(/::/)[-1].sub(/Job/, "")
  end

  def output?
    (log && File.size?(log)).to_i > 0
  end

  def output(offset = 0)
    data = ""
    if log && File.exists?(log)
      File.open(log, "r") do |f|
	f.seek(offset.to_i)
	data = f.read
      end
    end
    data
  end

  def type
    self[:type].sub(/Job$/, "") if self[:type]
  end

  def state
    self[:state].to_sym if !self[:state].blank?
  end

  def completed?
    success? || failure?
  end

  # Mixin...
  def haml_object_ref
    "job"
  end

  # @job.execute
  # @job.delay.execute
  # def execute
  # end

  def perform
    save! if new_record?
    options[:log] = log
    running!
    update_attribute(:result, run)
  ensure
    options.delete(:log)
  end

  # job is Delayed::Backend::ActiveRecord::Job
  def enqueue(job)
    queued!
  end

  def success(job)
    success!
  end

  def error(job, exception)
    update_attributes(:state => :failure, :exceptions => exception)
  end

  def failure
    failure!
  end

  def target
    _target
  end

  def priority
    self[:priority].respond_to?(:to_sym) ? self[:priority].to_sym : :normal
  end

  def to_s
    return "" unless type

    s = "#{type} Job"
    s << ": #{target}" if target.present?
    s
  end

  protected

  def set_target
    self[:target] = target
  end

  def numeric_priority
    # Lower number == higher priority
    priority == :next ?
      [ Delayed::Job.minimum(:priority).to_i, 0 ].min - 1 :
      PRIORITY[priority]
  end

  def enqueue_delayed_job
    transaction do
      # Uh, why not just has_one..?
      job = Delayed::Job.enqueue(self, :priority => numeric_priority)
      update_column(:job_id, job.id)
    end
  end

  def dequeue_delayed_job
    # what if running... raise error?
    Delayed::Job.delete(job_id) if queued?
  end

  def _target
    # An ID to denote the job's target. E.g., package name, apple id, ...
  end

  # TODO: this should probably be moved to a the form class
  def typecast_options
    # For subclasses
  end

  def to_bool(val)
    case val
      when String
	val == "true" || val == "1" ? true : false
      when Fixnum
	val == 1 ? true : false
      else
	val
    end
  end

  def log
    if id?
      @log ||= File.join(config.output_log_directory || ".", "#{id}.log")
    end
  end

  def remove_log
    FileUtils.rm_f(log) if log && File.file?(log)
  end

  def itms
    @itms ||= ITunes::Store::Transporter.new(:path => config.path,
					     :print_stdout => true,
					     :print_stderr => true)
  end

  def config
    @confg ||= AppConfig.first_or_initialize
  end

  def self.order_by_column(order)
    column, direction = order.to_s.split(":")

    if column == "account"
      column = "accounts.username"
    # FIXME: we don't want to allow *all* columns
    elsif !column_names.include?(column)
      column = "created_at"
    end

    column << " " << (direction != "asc" ? "desc" : direction)
  end

  def self.build_search_query(where)
    q = {}
    [:priority, :target, :type, :state, :account_id].each { |k| q[k] = where[k] if where[k].present? }

    if where[:updated_at_from].present?
      d = []

      begin
        d << where[:updated_at_from].to_time(:local)
        d << (where[:updated_at_to].present? ? where[:updated_at_to].to_time(:local).end_of_day : d[0].end_of_day)
      rescue ArgumentError
        # Ignore invalid dates
        return q
      end

      q[:updated_at] = Range.new(*d)
    end

    q
  end
end
