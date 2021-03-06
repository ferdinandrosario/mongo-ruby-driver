require 'spec_helper'

describe 'Server Selection moving average round trip time calculation' do

  include Mongo::ServerSelection::RTT

  SERVER_SELECTION_RTT_TESTS.each do |file|

    spec = Mongo::ServerSelection::RTT::Spec.new(file)

    before(:all) do

      module Mongo
        class Server

          # We monkey-patch the monitor here, so the last average rtt can be controlled.
          # We keep the API of Monitor#initialize but add in an extra option and set the last rtt.
          #
          # @since 2.0.0
          class Monitor

            def initialize(address, listeners, options = {})
              @description = Mongo::Server::Description.new(address, {})
              @inspector = Mongo::Server::Description::Inspector.new(listeners)
              @options = options.freeze
              @connection = Connection.new(address, options)
              @last_round_trip_time = options[:avg_rtt_ms]
              @mutex = Mutex.new
            end

            private

            # We monkey patch this method to use an instance variable instead of calculating time elapsed.
            #
            # @since 2.0.0
            def average_round_trip_time(start)
              new_rtt = @new_rtt_ms
              RTT_WEIGHT_FACTOR * new_rtt + (1 - RTT_WEIGHT_FACTOR) * (@last_round_trip_time || new_rtt)
            end
          end
        end
      end
    end

    after(:all) do

      module Mongo
        class Server

          # Return the monitor implementation to its original for the other
          # tests in the suite.
          class Monitor

            # Create the new server monitor.
            #
            # @example Create the server monitor.
            #   Mongo::Server::Monitor.new(address, listeners)
            #
            # @param [ Address ] address The address to monitor.
            # @param [ Event::Listeners ] listeners The event listeners.
            # @param [ Hash ] options The options.
            #
            # @since 2.0.0
            def initialize(address, listeners, options = {})
              @description = Description.new(address, {})
              @inspector = Description::Inspector.new(listeners)
              @options = options.freeze
              @connection = Connection.new(address, options)
              @last_round_trip_time = nil
              @mutex = Mutex.new
            end

            private

            def average_round_trip_time(start)
              new_rtt = Time.now - start
              RTT_WEIGHT_FACTOR * new_rtt + (1 - RTT_WEIGHT_FACTOR) * (@last_round_trip_time || new_rtt)
            end
          end
        end
      end
    end

    context(spec.description) do

      let(:address) do
        Mongo::Address.new('127.0.0.1:27017')
      end

      let(:monitor) do
        Mongo::Server::Monitor.new(address, Mongo::Event::Listeners.new,
                                   TEST_OPTIONS.merge(avg_rtt_ms: spec.avg_rtt_ms))
      end

      before do
        monitor.instance_variable_set(:@new_rtt_ms, spec.new_rtt_ms)
        monitor.scan!
      end

      it 'correctly calculates the moving average round trip time' do
        expect(monitor.description.average_round_trip_time).to eq(spec.new_avg_rtt)
      end
    end
  end
end
