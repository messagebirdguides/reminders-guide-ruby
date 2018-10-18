require 'dotenv'
require 'sinatra'
require 'messagebird'
require 'active_support'
require 'active_support/core_ext'

set :root, File.dirname(__FILE__)

#  Load configuration from .env file
Dotenv.load if Sinatra::Base.development?

# Load and initialize MesageBird SDK
client = MessageBird::Client.new(ENV['MESSAGEBIRD_API_KEY'])

# Set up Appointment "Database"
appointment_database = []

# Display booking homepage
get '/' do
  # On the form, we're showing a default appointment
  # time 3:10 hours from now to simplify testing input
  default_dt = Time.now + 3.hours + 10.minutes
  erb :home, locals: {
    errors: nil,
    name: '',
    treatment: '',
    number: '',
    date: default_dt.strftime('%Y-%m-%d'),
    time: default_dt.strftime('%H:%M')
  }
end

def blank?(var)
  var.nil? || var.empty?
end

post '/book' do
  locals = {
    name: params[:name],
    treatment: params[:treatment],
    number: params[:number],
    date: params[:date],
    time: params[:time]
  }
  # Check if user has provided input for all form fields
  if blank?(params[:name]) || blank?(params[:treatment]) || blank?(params[:number]) || blank?(params[:date]) || blank?(params[:time])
    locals[:errors] = 'Please fill all required fields!'
    return erb :home, locals: locals
  end

  # Check if date/time is correct and at least 3:05 hours in the future
  earliest_possible_dt = Time.now + 3.hours + 5.minutes
  appointment_dt = DateTime.parse("#{params[:date]} #{params[:time]}")
  if appointment_dt < earliest_possible_dt
    # If not, show an error
    locals[:errors] = 'You can only book appointments that are at least 3 hours in the future!'
    return erb :home, locals: locals
  end

  # Check if phone number is valid
  begin
    lookup_response = client.lookup(params[:number], countryCode: ENV['COUNTRY_CODE'])

    # if lookup_response.type != "mobile" # The number lookup was successful but it is not a mobile number
    #   locals[:errors] = "You have entered a valid phone number, but it's not a mobile number! Provide a mobile number so we can contact you via SMS."
    #   return erb :home, locals: locals
    # else # Everything OK
    # Schedule reminder 3 hours prior to the treatment
    reminder_dt = appointment_dt - 3.hours
    body = "#{locals[:name]}, here's a reminder that you have a #{locals[:treatment]} scheduled for #{appointment_dt.strftime('%H:%M')}. See you soon!"

    begin
      message_response = client.message_create("BeautyBird", [lookup_response.phoneNumber], body, scheduledDatetime: appointment_dt)

      # Request was successful
      puts message_response

      # Create and persist appointment object
      appointment = {
        name: params[:name],
        treatment: params[:treatment],
        number: params[:number],
        appointment_dt: appointment_dt.strftime('%Y-%m-%d %H:%M'),
        reminder_dt: reminder_dt.strftime('%Y-%m-%d %H:%M')
      }
      appointment_database << appointment

      # Render confirmation page
      return erb :confirm, locals: { appointment: appointment }
    rescue MessageBird::ErrorException => ex
      errors = ex.errors.each_with_object([]) do |error, memo|
        memo << "Error code #{error.code}: #{error.description}"
      end.join("\n")

      return erb :home, locals: { errors: errors }
    end
    # end
  rescue MessageBird::InvalidPhoneNumberException => ex
    # This error code indicates that the phone number has an unknown format
    locals[:errors] = "You need to enter a valid phone number!"
    return erb :home, locals: locals
  rescue MessageBird::ErrorException => ex
    # Some other error occurred
    locals[:errors] = "Something went wrong while checking your phone number!"

    return erb :home, locals: locals
  end
end
