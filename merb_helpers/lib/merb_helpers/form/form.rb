module Merb
  class Form
    def initialize(obj, name, origin)
      @obj, @origin = obj, origin
      @name = name || @obj.class.name.snake_case.split("/").last
    end
    
    def concat(attrs, &blk)
      @origin.concat(@origin.capture(&blk), blk.binding)
    end
    
    def fieldset(attrs, &blk)
      legend = (l_attr = attrs.delete(:legend)) ? tag(:legend, l_attr) : ""
      contents = tag(:fieldset, legend + @origin.capture(&blk), attrs)
      @origin.concat(contents, blk.binding)
    end
    
    def form_tag(attrs = {}, &blk)      
      captured = @origin.capture(&blk)
      fake_method_tag = process_form_attrs(attrs)      
      
      contents = tag(:form, fake_method_tag + captured, attrs)
      @origin.concat(contents, blk.binding)
    end
    
    def process_form_attrs(attrs)
      method = attrs[:method]

      # Unless the method is :get, fake out the method using :post
      attrs[:method] = :post unless attrs[:method] == :get
      # Use a fake PUT if the object is not new, otherwise use the method
      # passed in.
      method = @obj && !@obj.new_record? ? :put : method || :post
      
      attrs[:enctype] = "multipart/form-data" if attrs.delete(:multipart) || @multipart
      
      method == :post || method == :get ? "" : fake_out_method(attrs, method)
    end
    
    # This can be overridden to use another method to fake out methods
    def fake_out_method(attrs, method)
      self_closing_tag(:input, :type => "hidden", 
        :name => "_method", :value => method)
    end
    
    def add_class(attrs, new_class)
      attrs[:class] = (attrs[:class].to_s.split(" ") + [new_class]).join(" ")
    end

    def update_control_fields(method, attrs, type)
      case type
      when "select"
        update_select_control_fields(method, attrs)
      end
    end
    
    def update_fields(attrs, type)
      case type
      when "checkbox"
        update_checkbox_field(attrs)
      when "file"
        @multipart = true
      end
    end
    
    def update_select_control_fields(method, attrs)
      attrs[:value_method] ||= method
      attrs[:text_method] ||= attrs[:value_method] || :to_s
      attrs[:selected] ||= @obj.send(attrs[:value_method])
    end
    
    def update_checkbox_field(attrs)
      on, off = attrs.delete(:on) || "1", attrs.delete(:off) || "0"
      checked = considered_true?(attrs.delete(:value))
      attrs[:value] = checked ? on : off
      attrs[:checked] = "checked" if checked
    end

    %w(text radio password hidden checkbox file).each do |kind|
      self.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{kind}_control(method, attrs = {})
          name = control_name(method)
          update_control_fields(method, attrs, "#{kind}")
          #{kind}_field({:name => name, :value => @obj.send(method)}.merge(attrs))
        end
        
        def #{kind}_field(attrs = {})
          update_fields(attrs, "#{kind}")
          self_closing_tag(:input, {:type => "#{kind}"}.merge(attrs))
        end
      RUBY
    end
    
    def submit(contents, attrs)
      attrs[:type] ||= "submit"
      attrs[:name] ||= "submit"
      update_fields(attrs, "submit")
      tag(:button, contents, attrs)
    end
    
    def select_control(method, attrs = {})
      name = control_name(method)
      update_control_fields(method, attrs, "select")
      select_field({:name => name}.merge(attrs))
    end
    
    def select_field(attrs = {})
      update_fields(attrs, "select")
      tag(:select, options_for(attrs), attrs)
    end
    
    def radio_group_control(method, arr)
      val = @obj.send(method)
      arr.map do |attrs|
        attrs = {:value => attrs} unless attrs.is_a?(Hash)
        attrs[:checked] ||= (val == attrs[:value])
        radio_group_item(method, attrs)
      end.join
    end
    
    def text_area_field(contents, attrs = {})
      update_fields(attrs, "text_area")
      tag(:textarea, contents, attrs)
    end
    
    def text_area_control(method, attrs = {})
      name = "#{@name}[#{method}]"
      update_control_fields(method, attrs, "text_area")
      text_area_field(@obj.send(method), 
        {:name => name}.merge(attrs))
    end
    
    private
    def control_name(method)
      "#{@name}[#{method}]"
    end
    
    def options_for(attrs)
      if attrs.delete(:include_blank)
        b = tag(:option, "", :value => "")
      elsif prompt = attrs.delete(:prompt)
        b = tag(:option, prompt, :value => "")
      else
        b = ""
      end
      
      # yank out the options attrs
      collection = attrs.delete(:collection) || []
      selected = attrs.delete(:selected)
      text_method = @obj ? attrs.delete(:text_method) : :last
      value_method = @obj ? attrs.delete(:value_method) : :first

      # if the collection is a Hash, optgroups are a-coming
      if collection.is_a?(Hash)
        options = collection.map do |g,col|
          tag(:optgroup, 
            options(col, text_method, value_method, attrs, selected, ""),
            :label => g)
        end + [b]
        options.join
      else
        options(collection, text_method, value_method, attrs, selected, b)
      end
    end
    
    def options(col, text_meth, value_meth, attrs, sel, b)
      options = col.map do |item|
        value = item.send(value_meth)
        attrs.merge!(:value => value)
        attrs.merge!(:selected => "selected") if value == sel
        tag(:option, item.send(text_meth), attrs)
      end + [b]
      options.join
    end
    
    def radio_group_item(method, attrs)
      attrs.merge!(:checked => "checked") if attrs[:checked]
      radio_control(method, attrs)
    end
    
    def considered_true?(value)
      value && value != "0" && value != 0
    end
  end
  
  class CompleteForm < Form
    def update_control_fields(method, attrs, type)
      attrs.merge!(:id => "#{@name}_#{method}") unless attrs[:id]
      super
    end
    
    def update_fields(attrs, type)
      case type
      when "text", "radio", "password", "hidden", "checkbox", "file"
        add_class(attrs, type)
      end
      super
    end
    
    def label(attrs)
      attrs ||= {}
      for_attr = attrs[:id] ? {:for => attrs[:id]} : {}
      if label_text = attrs.delete(:label)
        tag(:label, label_text, for_attr)
      else 
        ""
      end
    end
    
    %w(text password file).each do |kind|
      self.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{kind}_field(attrs = {})
          label(attrs) + super
        end
      RUBY
    end
    
    def submit(contents, attrs = {})
      label(attrs) + super
    end
    
    def text_area_field(contents, attrs = {})
      label(attrs) + super
    end
    
    def checkbox_field(attrs = {})
      label_text = label(attrs)
      super + label_text
    end
    
    def radio_field(attrs = {})
      label_text = label(attrs)
      super + label_text
    end
    
    def radio_group_item(method, attrs)
      unless attrs[:id]
        attrs.merge!(:id => "#{@name}_#{method}_#{attrs[:value]}")
      end
      
      attrs.merge!(:label => attrs[:label] || attrs[:value])
      super
    end
    
    def hidden_field(attrs = {})
      attrs.delete(:label)
      super
    end
    
  end
  
  class CompleteFormWithErrors < CompleteForm
    def update_control_fields(method, attrs, type)
      if @obj.errors.on(method.to_sym)
        add_class(attrs, "error")
      end
      super
    end    
  end
  
end