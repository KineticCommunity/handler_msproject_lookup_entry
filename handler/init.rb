# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class MsprojectLookupEntryV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'

    # Store parameters values in a Hash of parameter names to values.
    @parameters = {}
    REXML::XPath.match(@input_document, '/handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end
  end

  def execute()
    resources_path = File.join(File.expand_path(File.dirname(__FILE__)), 'resources')

    # Create the command string that will be used to retrieve the cookies
    cmd_string = "O365Auth.Console.exe #{@info_values['ms_project_location']} #{@info_values['username']} #{@info_values['password']} #{@info_values['integrated_authentication']}"

    # Retrieve the cookies
    cookies = `cd "#{resources_path}" & #{cmd_string}`

    lookup_table = @parameters['lookup_table'].gsub(" ","+")
    lookup_entry = @parameters['lookup_entry'].gsub(" ","+")

    proj_resource = RestClient::Resource.new(@info_values['ms_project_location'].chomp("/"),
      :headers => { :cookie => cookies})
    table_endpoint = proj_resource["/_api/ProjectServer/LookupTables"]

    puts "Sending the request to find the Lookup Table Id for '#{@parameters['lookup_table']}'" if @enable_debug_logging
    begin
      results = table_endpoint["?$filter=Name+eq+'#{lookup_table}'"].get :accept => 'application/json'
    rescue RestClient::BadRequest => error
      raise StandardError, error.inspect
    end

    json = JSON.parse(results)
    # Get the JSON value array that contains the lookup table information
    value = json["value"]
    if value.size != 1
      raise StandardError, "The lookup table '#{@parameters['lookup_table']}' could not be found."
    else
      id = value[0]["Id"]
    end

    puts "The Id of the Lookup Table '#{@parameters['lookup_table']}' is '#{id}'" if @enable_debug_logging

    entry_endpoint = proj_resource["/_api/ProjectServer/LookupTables('#{id}')/Entries"]

    puts "Sending the request to the Lookup Table '#{@parameters['lookup_table']}' to find the FullValue '#{@parameters['lookup_entry']}'" if @enable_debug_logging
    begin
      results = entry_endpoint["?$filter=FullValue+eq+'#{lookup_entry}'"].get :accept => 'application/json'
    rescue RestClient::BadRequest => error
      raise StandardError, error.inspect
    end

    json = JSON.parse(results)
    # Get the JSON value array that contains the lookup entry information
    value = json["value"]
    if value.size != 1
      puts "The lookup entry '#{@parameters['lookup_entry']}' could not be found in the table '#{@parameters['lookup_table']}'." if @enable_debug_logging
      entry_id = nil
    else
      entry_id = value[0]["Id"]
    end

    puts "The Id of the Lookup Table '#{@parameters['lookup_table']}' is '#{id}'" if @enable_debug_logging

    puts "Returning results" if @enable_debug_logging
    <<-RESULTS
    <results>
      <result name="entry_id">#{entry_id}</result>
    </results>
    RESULTS
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end