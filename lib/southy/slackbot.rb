require 'slack-ruby-client'
require 'set'

module Southy
  class Slackbot
    def initialize(config, travel_agent)
      @config = config
      @agent = travel_agent
      @channels = Set.new

      @conversions = {
        'Yasmine Molavi' => [ 'Yasaman', 'Molavi Vassei' ]
      }

      Slack.configure do |slack_cfg|
        slack_cfg.token = @config.slack_api_token
      end

      Slack::RealTime.configure do |slack_cfg|
        slack_cfg.concurrency = Slack::RealTime::Concurrency::Async
      end

      @webclient = Slack::Web::Client.new
    end

    def slack_users
      @slack_users ||= get_slack_users
    end

    def run
      auth = @webclient.auth_test
      if auth['ok']
        puts "Slackbot is active!"
        puts "Accepting channels: #{@config.slack_accept_channels}" if @config.slack_accept_channels.length > 0
        puts "Ignoring channels: #{@config.slack_reject_channels}" if @config.slack_reject_channels.length > 0
      else
        puts
        puts "Slackbot is doomed :-("
        return
      end

      client = Slack::RealTime::Client.new

      client.on :hello do
        puts "Slackbot real time messaging is up and running as #{client.self.name}"
      end

      client.on :message do |data|
        next if data['user'] == 'U0HM6QX8Q' # this is Mr. Southy!
        next unless data['text']
        tokens = data['text'].split(' ').map { |t| strip_markdown(t) }
        channel = data['channel']
        next unless tokens.length > 0
        next unless tokens[0].downcase == 'southy'
        next if @config.slack_accept_channels.length > 0 and ! @config.slack_accept_channels.index(channel)
        next if @config.slack_reject_channels.index channel
        message = Southy::Message.new client, channel
        message.type
        @channels << channel
        ( help(data, [], message) and next ) unless tokens[1]
        method = tokens[1].downcase
        args = tokens[2..-1]
        method = "#{method}_all" if args == [ 'all' ]
        if respond_to? method
          send method, data, args, message
        else
          message.reply "I don't know how to `#{method}`"
          help data, [], message
        end
      end

      client.start!
    end

    def fuzzy_find_slack_users(fuzz)
      options = [ fuzz ]
      options << fuzz[1..-1] if fuzz =~ /^@/
      return slack_users.select { |su| options.include?(su.name)    ||
                                       options.include?(su.profile.email) ||
                                       options.include?("#{su.profile.first_name} #{su.profile.last_name}")
                                }
    end

    def slack_users_to_notify(reservation)
      return fuzzy_find_slack_users @config.fake_slack_user if @config.fake_slack_user

      email_slack_user = slack_users.find { |su| su.profile.email == reservation.email }
      name_slack_users = reservation.passengers.map { |p| slack_users.find { |su| p.name_matches? "#{su.profile.first_name} #{su.profile.last_name}" } }.compact
      to_notify = Set.new(name_slack_users)
      to_notify << email_slack_user if email_slack_user
      to_notify
    end

    def notify(reservation, bounds, message)
      return unless @config.notify_users?

      itinerary = "```#{Reservation.list(bounds, short: true)}```"

      slack_users_to_notify(reservation).each do |su|
        next if @config.test?

        resp = @webclient.conversations_open users: su.id
        @webclient.chat_postMessage channel: resp.channel.id, text: message,   as_user: true
        @webclient.chat_postMessage channel: resp.channel.id, text: itinerary, as_user: true
      end
    end

    def notify_reconfirmed(reservation)
      message = "Your reservation has been _updated_ for `#{reservation.conf}`."
      notify reservation, reservation.bounds, message
    end

    def notify_checked_in(bound)
      message = "Your party has been checked in to flight `SW#{bound.flights.first}`"
      notify bound.reservation, [bound], message
    end

    def notify_canceled(reservation)
      message = "Your reservation has been _canceled_ for `#{reservation.conf}`."
      notify reservation, reservation.bounds, message
    end

    def user_profile(data)
      id = data['user']
      res = @webclient.users_info user: id
      return {} unless res['ok']
      profile = res['user']['profile']
      first = profile['first_name']
      last = profile['last_name']
      converted = @conversions["#{first} #{last}"]
      if converted
        first = converted[0]
        last = converted[1]
      end
      { id: id, first_name: first, last_name: last, full_name: "#{first} #{last}", email: profile['email'] }
    end

    def help(data, args, message)
      message.reply "Hello, I am Southy.  I can do the following things:"
      message.reply <<EOM
```
southy help                 Show this message
southy hello                Say hello to me!
southy whatsup              Show me ALL the flights upcoming
southy list                 Show me what flights I have upcoming
southy history              Show me what flights I had in the past
southy search <name>        Search upcoming flights by a first or last name
southy info <conf>          Show me details for a specific reservation
southy add <conf>           Add this flight to Southy
southy remove <conf>        Remove this flight from Southy
southy reconfirm [<confs>]  Reconfirm your flights, if you have changed flight info

<conf> = Your flight confirmation number and optionally contact info, for example:
         southy add RB7L6K     <-- uses your name and email from Slack
         southy add RB7L6K Joey Shabadoo joey@snpp.com
```
EOM
    end

    def blowup(data, args, message)
      message.reply "Tick... tick... tick... BOOM!   Goodbye."
      raise Exception.new("kablammo!")
    end

    def hello(data, args, message)
      profile = user_profile data
      if profile[:first_name] and profile[:last_name] and profile[:email]
        message.reply "Hello #{profile[:first_name]}!  You are all set to use Southy."
        message.reply "I will use this information when looking up your flights:"
        message.reply <<EOM
```
name:  #{profile[:first_name]} #{profile[:last_name]}
email: #{profile[:email]}
```
EOM
      else
        message.reply "Hello.  You are not set up yet to use Southy.  You need to fill in your first name, last name and email in your Slack profile."
      end
    end

    def print_info(reservation, message)
      message.reply "```#{reservation.info}```"
    end

    def info(data, args, message)
      if args.length == 0
        message.reply 'No confirmation number provided'
        return
      end

      reservation = Reservation.for_conf(args[0]).first
      unless reservation
        message.reply 'No reservation found'
        return
      end

      confirm_reservations [reservation], message
      print_info reservation, message
    end

    def print_bounds(bounds, message)
      if !bounds || bounds.empty?
        message.reply "```No available flights.```"
        return
      end

      all = Reservation.list bounds, short: true
      all.split("\n").each_slice(40) do |slice|
        message.reply "```#{slice.join("\n")}```"
      end
    end

    def list(data, args, message)
      profile = user_profile data
      message.reply "Upcoming Southwest flights for #{profile[:full_name]}:"
      message.type
      if args && args.length > 0
        bounds = Bound.upcoming.for_reservation args[0]
      else
        bounds = Bound.upcoming.for_person profile[:id], profile[:email], profile[:full_name]
      end
      print_bounds bounds, message
    end

    def list_all(data, args, message)
      message.reply "Upcoming Southwest flights:"
      message.type
      bounds = Bound.upcoming
      print_bounds bounds, message
    end

    def whatup(data, args, message)
      whatsup data, args, message
    end

    def whatsup(data, args, message)
      list_all data, args, message
      message.reply "```You can type 'southy help' to see more commands```"
    end

    def history(data, args, message)
      profile = user_profile data
      message.reply "Previous Southwest flights for #{profile[:full_name]}:"
      message.type
      bounds = Bound.past.for_person profile[:id], profile[:email], profile[:full_name]
      print_bounds bounds, message
    end

    def history_all(data, args, message)
      message.reply "Previous Southwest flights:"
      message.type
      bounds = Bound.past
      print_bounds bounds, message
    end

    def search(data, args, message)
      if args.length == 0
        message.reply 'No search value provided'
        return
      end

      message.type
      bounds = Bound.upcoming.search args[0]
      print_bounds bounds, message
    end

    def add(data, args, message)
      args.tap do |(conf, fname, lname, email)|
        return ( message.reply "You didn't enter a confirmation number!" ) unless conf

        if Bound.for_reservation(conf).length > 0
          message.reply "That reservation already exists. Try `southy reconfirm #{conf}`"
          return
        end

        profile = user_profile data
        unless fname and lname
          fname = profile[:first_name]
          lname = profile[:last_name]
        end
        unless email
          email = profile[:email]
        end
        if email && match = email.match(/^<mailto:(.*)\|/)
          email = match.captures[0]
        end

        reservation = confirm_reservation conf, fname, lname, email, message
        if reservation
          reservation.created_by = profile[:id]
          reservation.save!
          print_bounds reservation&.bounds, message
        end
      end
    end

    def remove(data, args, message)
      args.tap do |(conf)|
        return ( message.reply "You didn't enter a confirmation number!" ) unless conf
        deleted = Reservation.for_conf(conf).destroy_all
        response = "Removed #{deleted.length} reservation(s) - #{deleted.map(&:conf).join(', ')}"
        message.reply response
        puts response
      end
    end

    def reconfirm(data, args, message)
      if args.length > 0
        reservations = Reservation.for_confs args
        if reservations.empty?
          message.reply "No flights available for confirmations: #{args}"
          return
        end
      else
        profile = user_profile data
        reservations = Reservation.upcoming.for_person profile[:id], profile[:email], profile[:full_name]
        if reservations.empty?
          message.reply "No flights available for #{profile[:full_name]}"
          return
        end
      end

      reservations = confirm_reservations reservations, message
      print_bounds reservations.map(&:bounds).flatten, message
    end

    def reconfirm_all(data, args, message)
      reservations = Reservation.upcoming
      if reservations.empty?
        message.reply "No flights available"
        return
      end

      reservations = confirm_reservations reservations, message
      print_bounds reservations.map(&:bounds).flatten, message
    end

    private

    def confirm_reservation(conf, first, last, email, message)
      print "Confirming #{conf} for #{first} #{last}... "
      message.reply "Confirming #{conf} for *#{first} #{last}*..."
      message.type
      reservation, is_new = @agent.confirm conf, first, last, email, false
      puts ( is_new ? "success" : "no changes" )
      reservation
    rescue SouthyException => e
      puts e.message
      message.reply "Could not confirm reservation #{conf} - #{e.message}"
      nil
    end

    def confirm_reservations(reservations, message)
      reservations.sort_by { |r| r.bounds.first.departure_time }.map do |r|
        confirm_reservation r.conf, r.first_name, r.last_name, r.email, message
      end.compact
    end

    def get_slack_users
      #print "Getting users from Slack... "
      resp = @webclient.users_list
      throw resp unless resp.ok
      users = resp.members.map do |member|
        next unless member.profile.email # no bots
        next if member.deleted # no ghosts
        member
      end
      #puts "done (#{users.length} users)"
      users.compact
    rescue => e
      #puts e.message
      raise e
    end

    def strip_markdown(str)
      if str.first == str.last && str.first =~ /[\*_~]/
        return strip_markdown str[1..-2]
      end

      str
    end
  end
end
