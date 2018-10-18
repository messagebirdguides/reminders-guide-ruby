# SMS Appointment Reminders

### ⏱ 15 min build time

## Why build SMS appointment reminders?

Booking appointments online from a website or mobile app is quick and easy. Customers just have to select their desired date and time, enter their personal details and hit a button. The problem, however, is that easy-to-book appointments are often just as easy to forget.

For appointment-based services, no-shows are annoying and costly because of the time and revenue lost waiting for a customer instead of serving them, or another customer. Timely SMS reminders act as a simple and discrete nudges, which can go a long way in the prevention of costly no-shows.

## Getting Started

In this MessageBird Developer Guide, we'll show you how to use the MessageBird SMS messaging API to build an SMS appointment reminder application in Ruby.

This sample application represents the order website of a fictitious online beauty salon called _BeautyBird_. To reduce the growing number of no-shows, BeautyBird now collects appointment bookings through a form on their website and schedules timely SMS reminders to be sent out three hours before the selected date and time.

To look at the full sample application or run it on your computer, go to the [MessageBird Developer Guides GitHub repository](https://github.com/messagebirdguides/reminders-guide-ruby) and clone it or download the source code as a ZIP archive. You will need [Ruby](https://www.ruby-lang.org/en/) and [bundler](https://bundler.io/) to run the example.

Open a console pointed at the directory into which you've placed the sample application and run the following command to install the MessageBird SDK for Ruby and other dependencies:

```
bundle install
```

## Configuring the MessageBird SDK

The SDK is loaded with the following lines in `app.rb`:

``` ruby
require 'dotenv'
require 'sinatra'
require 'messagebird'

set :root, File.dirname(__FILE__)
Dotenv.load if Sinatra::Base.development?

client = MessageBird::Client.new(ENV['MESSAGEBIRD_API_KEY'])
```

The MessageBird API key needs to be provided as a parameter.

Pro-tip: Hardcoding your credentials in the code is a risky practice that should never be used in production applications. A better method, also recommended by the Twelve-Factor App Definition, is to use environment variables. We've added dotenv to the sample application, so you can supply your API key in a file named .env, too:

**Pro-tip:** Hardcoding your credentials is a risky practice that should never be used in production applications. A better method, also recommended by the [Twelve-Factor App Definition](https://12factor.net/), is to use environment variables.

We've added [dotenv](https://rubygems.org/gems/dotenv) to the sample application, so you can supply your API key in a file named `.env`. You can copy the provided file `env.example` to `.env` and add your API key like this:

```
MESSAGEBIRD_API_KEY=YOUR-API-KEY
```

API keys can be created or retrieved from the API access (REST) tab in the Developers section of your MessageBird account.

## Collecting User Input

In order to send SMS messages to users, you need to collect their phone number as part of the booking process. We have created a sample form that asks the user for their name, desired treatment, number, date and time. For HTML forms it's recommended to use `type="tel"` for the phone number input. You can see the template for the complete form in the file `views/home.erb` and the route that drives it is defined as `get '/'` in `app.rb`.

## Storing Appointments & Scheduling Reminders

The user's input is sent to the route `post '/book'` defined in `app.rb`. The implementation covers the following steps:

### Step 1: Check their input

Validate that the user has entered a value for every field in the form.

### Step 2: Check the appointment date and time

Confirm that the date and time are valid and at least three hours and five minutes in the future. BeautyBird won't take bookings on shorter notice. Also, since we want to schedule reminders three hours before the treatment, anything else doesn't make sense from a testing perspective. We recommend using a library such as [`activesupport/duration`](https://rubygems.org/gems/activesupport), which makes working with date and time calculations a breeze. Don't worry, we've already integrated it into our sample application:

``` ruby
# Check if date/time is correct and at least 3:05 hours in the future
earliest_possible_dt = Time.now + 3.hours + 5.minutes
appointment_dt = DateTime.parse("#{params[:date]} #{params[:time]}")
if (appointment_dt < earliest_possible_dt)
  # If not, show an error
  # ...
```

## Step 3: Check their phone number

Check whether the phone number is correct. This can be done with the [MessageBird Lookup API](https://developers.messagebird.com/docs/lookup#lookup-request), which takes a phone number entered by a user, validates the format and returns information about the number, such as whether it is a mobile or fixed line number. This API doesn't enforce a specific format for the number but rather understands a variety of different variants for writing a phone number, for example using different separator characters between digits, giving your users the flexibility to enter their number in various ways. In the SDK, you can call `client.lookup`:

``` ruby
# Check if phone number is valid
lookup = messagebird.lookup(params[:number], countryCode: process.env.COUNTRY_CODE)
```

The function takes two arguments: the phone number and a country code. Providing a default country code enables users to supply their number in a local format, without the country code.

To add a country code, add the following line to you `.env` file, replacing NL with your own ISO country code:

```
COUNTRY_CODE=NL
```

In the `lookup` response, we handle four different cases:

* An error (code 21) occurred, which means MessageBird was unable to parse the phone number.
* Another error code occurred, which means something else went wrong in the API.
* No error occurred, but the value of the response's type attribute is something other than mobile.
* Everything is OK, which means a mobile number was provided successfully.

``` ruby
begin
  locals = {
    name: params[:name],
    treatment: params[:treatment],
    number: params[:number],
    date: params[:date],
    time: params[:time]
  }

  lookup_response = client.lookup(params[:number], countryCode: ENV['COUNTRY_CODE'])

  if lookup_response.type != "mobile" # The number lookup was successful but it is not a mobile number
    locals[:errors] = "You have entered a valid phone number, but it's not a mobile number! Provide a mobile number so we can contact you via SMS."
    return erb :home, locals: locals
  else # Everything OK

  end
rescue MessageBird::InvalidPhoneNumberException => ex
  # This error code indicates that the phone number has an unknown format
  locals[:errors] = "You need to enter a valid phone number!"
  return erb :home, locals: locals
rescue MessageBird::ErrorException => ex
  # Some other error occurred
  locals[:errors] = "Something went wrong while checking your phone number!"

  return erb :home, locals: locals
end
```

The implementation for the following steps is contained within the `Everything OK` block.

## Step 4: Schedule the reminder

Using `activesupport`, we can easily specify the time for our reminder:

``` ruby
#Schedule reminder 3 hours prior to the treatment
reminder_dt = appointment_dt - 3.hours
```

Then it's time to call MessageBird's API:

``` ruby
# Send scheduled message with MessageBird API
body = "#{params[:name]}, here's a reminder that you have a #{params[:treatment]} scheduled for #{appointment_dt.strftime('%H:%M')}. See you soon!"
message_response = client.message_create("BeautyBird", [lookup_response.phoneNumber], body, scheduledDatetime: appointment_dt)
```

Let's break down the parameters that are set with this call of `client.message_create`:

* `originator`: This is the first parameter. It represents the sender ID. You can use a mobile number here, or an alphanumeric ID, like in the example.
* `recipients`: This is the second parameter. It's an array of phone numbers. We just need one number, and we're using the normalized number returned from the Lookup API instead of the user-provided input.
* `body`: This is the hird parameter. It's the friendly text for the message.
* `scheduledDatetime`: This is one of the many options you can pass as a Hash. It instructs MessageBird not to send the message immediately but at a given timestamp, which we've defined previously.

## Step 5: Store the appointment

We're almost done! The application's logic continues with the `message_response`, where we need to handle both success and error cases:

``` ruby
begin
  message_response = client.message_create("BeautyBird", [lookup.phoneNumber], body, scheduledDatetime: appointment_dt)

  # Request was successful
  puts message_response

  # Create and persist appointment object
  appointment = {
    name: params[:name],
    treatment: params[:treatment],
    number: params[:number],
    appointment_dt: appointment_dt.strftime('%Y-%m-%d HH:mm'),
    reminder_dr: reminder_dt.strftime('%Y-%m-%d %H:%M')
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
```

As you can see, for the purpose of the sample application, we simply "persist" the appointment to a global variable in memory. This is where, in practical applications, you would write the appointment to a persistence layer such as a file or database. We also show a confirmation page, which is defined in `views/confirm.erb`.

## Testing the Application

Now, let's run the following command from your console:

```
ruby app.rb
```

Then, point your browser at `localhost:4567` to see the form and schedule your appointment! If you've used a live API key, a message will arrive to your phone three hours before the appointment! But don't actually leave the house, this is just a demo :)

## Nice work!

You now have a running SMS appointment reminder application!

You can now use the flow, code snippets and UI examples from this tutorial as an inspiration to build your own SMS reminder system. Don't forget to download the code from the [MessageBird Developer Guides GitHub repository](https://github.com/messagebirdguides/reminders-guide-ruby).

## Next steps

Want to build something similar but not quite sure how to get started? Please feel free to let us know at support@messagebird.com, we'd love to help!
