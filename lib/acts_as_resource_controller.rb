module ActsAsResourceController

  def self.included(base) # :nodoc:
    base.extend ClassMethods
  end

  module ClassMethods

    def acts_as_resource_controller options = {}
      include ResourceMethods

      if block_given?
        options.instance_eval do
          def method_missing(method, *args)
            self[method.to_sym] = args.first
          end
        end
        yield(options)
      end

      rescue_from ActiveRecord::RecordInvalid,  :with => :render_invalid_record
      rescue_from ActiveRecord::RecordNotFound, :with => :render_record_not_found

      %w(belongs_to after_create after_update format_options filter_update_params).each do |o|
        define_method(o) { options[o.to_sym] }
      end
      define_method(:order)        { options[:order] || 'id ASC' }
      define_method(:conditions)   { (options[:conditions] ||= []).map { |v| v.is_a?(Proc) ? v.call(self) : v } }
      define_method(:joins)        { options[:joins].is_a?(Symbol) ? ",#{options[:joins]}" : options[:joins] }
    end

  end# ClassMethods

  module ResourceMethods

    def index
      self.instances = with_scope do
        options = returning(:order => order) do |o|
          o[:conditions] = ["#{belongs_to_id} = ?", params[belongs_to_id]] if belongs_to?
          o[:joins] = joins unless joins.nil?
        end
        model.find :all, options
      end
      render_formats instances, true
    end

    def show
      self.instance = with_scope { model.find params[:id] }
      render_formats instance
    end

    def create
      m = model.new params[model_name]
      m.send("#{belongs_to_id}=", params[belongs_to_id]) if belongs_to?
      self.instance = m
      m.save!
      headers['Location'] = send "#{model_name}_url", instance
      send(after_create) unless after_create.nil?
      head :created
    end
    
    def edit
      self.instance = model.find params[:id]
    end

    def update
      self.instance = model.find params[:id]
      instance.update_attributes!(filter_update_params.nil? ? params[model_name] : send(filter_update_params, params[model_name]))
      send(after_update) unless after_update.nil?
      render_formats instance
    end

    def destroy
      model.destroy with_scope { model.find params[:id] }
      head :ok
    end

  private
  
    def with_scope
      opts = { :conditions => conditions }
      opts[:joins] = joins unless joins.nil?
      model.send(:with_scope, :find => opts) { yield }
    end

    def belongs_to?
      !belongs_to.nil? && !params[belongs_to_id].nil?
    end

    def belongs_to_id
      "#{belongs_to}_id"
    end

    def model_name
      @model_name ||= controller_name.singularize
    end

    def model
      @model ||= model_name.camelize.constantize
    end
    
    def instance=(value)
      instance_variable_set "@#{model_name}", value
    end
    
    def instance
      instance_variable_get "@#{model_name}"
    end
    
    def instances=(objects)
      instance_variable_set "@#{model_name.pluralize}", objects
    end
    
    def instances
      instance_variable_get "@#{model_name.pluralize}"
    end

    def extend_to_format obj
      obj.instance_variable_set "@format_options", format_options
      
      # TODO: refactore the lines below to an simple :format for loop
      obj.class.send(:alias_method, :to_json_orig, :to_json)
      def obj.to_json options = {}
        to_json_orig options.merge(@format_options)
      end
      obj.class.send(:alias_method, :to_xml_orig, :to_xml)
      def obj.to_xml options = {}
        to_xml_orig options.merge(@format_options)
      end
    end

    def render_formats data, list = false

      unless format_options.nil?
        if data.is_a? Array
          data.each {|obj| extend_to_format(obj) }
        else
          extend_to_format(data)
        end
      end

      respond_to do |format|
        format.html
        format.json { render :json => data }
        format.js { render :json => data, :content_type => 'application/json' }
        format.xml  { render :xml  => data }
      end
    end

    def render_invalid_record exception
      record = exception.record
      respond_to do |format|
        format.json { render :json => errors_as_hash(record.errors), :status => :unprocessable_entity }
        format.js   { render :json => errors_as_hash(record.errors), :status => :unprocessable_entity, :content_type => 'application/json' }
        format.xml  { render :xml => record.errors.full_messages,  :status => :unprocessable_entity }
      end
    end

    def errors_as_hash errors
      returning({}) { |h| errors.each { |attr, msg| h[attr] = msg.gsub(/%\{/, '#{') } }
    end

    def render_record_not_found exception
      respond_to do |format|
        format.json { render :json => exception.to_s, :status => :unprocessable_entity }
        format.js   { render :json => exception.to_s, :status => :unprocessable_entity, :content_type => 'application/json' }
        format.xml  { render :xml  => "<error>#{exception}</error>", :status => :unprocessable_entity }
      end
    end

  end# ResourceMethods

end# ActsAsResourceController
