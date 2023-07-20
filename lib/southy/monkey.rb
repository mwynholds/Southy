require 'json'
require 'net/https'
require 'fileutils'
require 'pp'
require 'tzinfo'
require 'ostruct'

module Southy
  class Monkey

    DEBUG = false

    def initialize(config = nil)
      @config = config

      @hostname = 'mobile.southwest.com'
      @api_key = 'l7xx44e0282659f14664b831eeba67b38a6e'
    end

    def parse_json(conf, response, name)
      if response.body == nil || response.body == ''
        raise SouthyException.new "empty response body - #{response.code} (#{response.msg})"
      end

      json = JSON.parse response.body
      @config.save_file conf, "#{name}.json", json

      JSON.parse response.body, object_class: OpenStruct
    end

    def fetch_trip_info(conf, first_name, last_name)
      uri = URI("https://#{@hostname}/api/mobile-air-booking/v1/mobile-air-booking/page/view-reservation/#{conf}")
      uri.query = URI.encode_www_form(
        'first-name' => first_name,
        'last-name'  => last_name
      )
      request = Net::HTTP::Get.new uri
      fetch_json conf, request, 'trip-info'
    end

    def try_all_names(first_name, last_name)
      names = Passenger.possible_names first_name, last_name
      json  = nil
      names.each do |f, l|
        json = yield f, l
        break if json.httpStatusCode != 'NOT_FOUND'
      end
      json
    end

    def lookup(conf, first_name, last_name)
      json = try_all_names first_name, last_name do |f, l|
        fetch_trip_info conf, f, l
      end

      status_code = json.httpStatusCode
      code        = json.code
      message     = json.message

      if status_code
        ident = "#{conf} #{first_name} #{last_name}"
        raise SouthyException.new("#{code} - #{message}", code)
      end

      page = json.viewReservationViewPage
      raise SouthyException.new("No reservation") unless page

      Reservation.from_json page
    end

    def fetch_checkin_info_1(conf, first_name, last_name)
      uri = URI("https://#{@hostname}/api/mobile-air-operations/v1/mobile-air-operations/page/check-in/#{conf}")
      uri.query = URI.encode_www_form(
        'first-name' => first_name,
        'last-name'  => last_name
      )
      request = Net::HTTP::Get.new uri
      fetch_json conf, request, 'checkin-info-1'
    end

    def fetch_checkin_info_2(conf, first_name, last_name, sessionToken)
      uri = URI("https://#{@hostname}/api/mobile-air-operations/v1/mobile-air-operations/page/check-in")
      request = Net::HTTP::Post.new uri
      request.body = {
        recordLocator: conf,
        firstName: first_name,
        lastName: last_name,
        checkInSessionToken: sessionToken
      }.to_json
      request.content_type = 'application/json'
      fetch_json conf, request, "checkin-info-2--#{first_name.downcase}-#{last_name.downcase}"
    end

    def checkin(reservation)
      json = try_all_names reservation.first_name, reservation.last_name do |f, l|
        fetch_checkin_info_1 reservation.conf, f, l
      end

      status_code = json.httpStatusCode
      code        = json.code
      message     = json.message

      if status_code
        raise SouthyException.new("#{code} - #{message}", code)
      end

      session_token = json.checkInSessionToken

      json = try_all_names reservation.first_name, reservation.last_name do |f, l|
        fetch_checkin_info_2 reservation.conf, f, l, session_token
      end

      status_code = json.httpStatusCode
      code        = json.code
      message     = json.message

      if status_code
        raise SouthyException.new("#{code} - #{message}", code)
      end

      errmsg = json.errmsg
      if errmsg
        raise SouthyException.new(errmsg)
      end

      page = json.checkInConfirmationPage
      unless page
        raise SouthyException.new("No check in information")
      end

      flight_nodes = page.flights

      flight_nodes.each do |flight_node|
        flight = flight_node.flightNumber
        bound  = reservation.bound_for flight
        raise SouthyException.new("Missing bound for flight #{flight}") unless bound

        flight_node.passengers.each do |passenger_node|
          name      = passenger_node.name
          passenger = reservation.passengers.find { |p| p.name == name }
          if passenger
            seat = Seat.new
            seat.group    = passenger_node.boardingGroup
            seat.position = passenger_node.boardingPosition
            seat.flight   = flight_node.flightNumber

            passenger.assign_seat seat, bound
          else
            raise SouthyException.new("Missing passenger #{passenger_node.name}")
          end
        end
      end

      reservation
    end

    private

    def fetch_json(conf, request, name, n=0)
      puts "Fetch #{request.path}" if DEBUG
      request['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 8_0 like Mac OS X) AppleWebKit/600.1.3 (KHTML, like Gecko) Version/8.0 Mobile/12A4345d Safari/600.1.4'
      request['x-api-key'] = @api_key
      request['x-channel-id'] = "MWEB"

      https = Net::HTTP.new @hostname, 443
      https.use_ssl = true
      https.verify_mode = OpenSSL::SSL::VERIFY_PEER
      https.verify_depth = 5
      response = https.request(request)

      json = parse_json conf, response, name

      if json.errmsg && json.opstatus && json.opstatus != 0 && n <= 10  # technical error, try again (for a while)
        fetch_json conf, request, name, n + 1
      else
        json
      end
    end
  end

  class TestMonkey < Monkey
    attr_accessor :json_num

    def initialize(dir)
      @dir = dir
    end

    def get_json(conf, name)
      fn = json_num ? "#{name}_#{json_num}" : name
      JSON.parse IO.read("#{@dir}/#{conf}/#{fn}.json"), object_class: OpenStruct
    end

    def fetch_trip_info(conf, first, last)
      get_json conf, "trip-info"
    end

    def fetch_checkin_info_1(conf, first, last)
      get_json conf, "checkin-info-1"
    end

    def fetch_checkin_info_2(conf, first, last, token)
      get_json conf, "checkin-info-2"
    end
  end
end
