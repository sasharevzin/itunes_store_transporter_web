require "ostruct"
require "options"

class JobForm < OpenStruct
  include ActiveModel::Validations
  validates_presence_of :username, :password

  def marshal_dump
    data = { :options => super.dup }
    data[:priority] = data[:options].delete(:priority) if data[:options].include?(:priority)
    data
  end
end

class UploadForm < JobForm
  include Options::Validations::Upload
  include Options::Validations::Package
end

class VerifyForm < JobForm
  include Options::Validations::Package
end

class SchemaForm < JobForm
  validates_presence_of :version_number
  validates_numericality_of :version_number, :greater_than => 0, :unless => lambda { |form| form.version_number.blank? }
  validates_inclusion_of :version_name, :in => %w[film tv], :message => "Must be film or TV"
  validates_inclusion_of :type, :in => %w[transitional strict], :message => "Must be transitional or strict"
  
  def marshal_dump
    data = super
    data[:options].except!(:version_name, :version_number)
    data[:options][:version] = [version_name, version_number].compact.join('')
    data
  end
end

class LookupForm < JobForm
  validates_presence_of :package_id_value, :message => "You must provide an Apple ID or Vendor ID"
  validates_inclusion_of :package_id, :in => %w[vendor_id apple_id], :message => "Must be vendor_id or apple_id"

  def marshal_dump
    data = super
    data[:options].except!(:package_id, :package_id_value)
    data[:options][package_id.to_sym] = package_id_value if package_id.respond_to?(:to_sym)
    data
  end
end

class StatusForm < JobForm
  # Without a custom message, the ID is dropped from vendor id when show in the form
  validates_presence_of :vendor_id, :message => "ID can't be blank"
end

class ProvidersForm < JobForm; end