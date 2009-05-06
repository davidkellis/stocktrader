$:.unshift File.join(File.dirname(__FILE__), '..', 'lib', 'strategies')

require 'buyandhold'

# this function assumes that the CSV files given to it cover a sufficient period of time
def scalable_randomized_buy_and_hold
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  pp tickers if $DEBUG
  
  max_trading_period = 15.minutes    # 3650.days = 2 days short of 10 years
  first_and_last_lines = ->(filename) { [File.new(filename).gets, File::ReadBackwards.new(filename).gets] }
  get_timestamp = ->(line) { Time.from_timestamp(line.strip.split(',').values_at(0..1).join('')) }
  time_between_first_and_last = ->(ticker) { times = first_and_last_lines.("#{ticker}.csv").map(&get_timestamp) ; times.last - times.first }
  tickers = tickers.select { |t|  time_between_first_and_last.(t) >= max_trading_period }
  pp tickers, tickers.length
  #return
  
  commission_fees = 7.00
  initial_deposit = 100000
  trial_count = 1000000
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  bah_strategies = Hash.new
  
  timestamp_specificity = 1.second
  timestamp_increment = 1.minute
  
  # ensure that timestamp_increment >= timestamp_specificity
  timestamp_increment = timestamp_increment < timestamp_specificity ? timestamp_specificity : timestamp_increment
  
  trading_intervals = [1.minute, 5.minutes, 15.minutes]
  
  last_symbol = nil
  trading_intervals.each do |trading_period_in_seconds|
    ticker_visitation_sequence = trial_count.times.map{ |i| tickers.rand }.sort
    
    ticker_visitation_sequence.each do |symbol|
      if symbol != last_symbol
        e.remove_price_history(last_symbol)       #remove the price-history for the previous symbol
        e.add_price_history(symbol)               #load the price-history for this symbol
        last_symbol = symbol
      end
      
      trading_start = Time.from_timestamp(e.price_histories[symbol].rand.timestamp)
      trading_end = trading_start + trading_period_in_seconds
      if trading_end.to_timestamp.to_i > e.price_histories[symbol].last.timestamp
        trading_end = Time.from_timestamp(e.price_histories[symbol].last.timestamp)
        trading_start = trading_end - trading_period_in_seconds
      end
      
      # Compute value of portfolio using Buy-And-Hold strategy
      a = scottrade.new_account(initial_deposit)
      bah = BuyAndHoldStrategy.new(a, [symbol], 0)
      #puts "start: #{trading_start} ; end: #{trading_end}, increment: #{trading_period_in_seconds} == #{trading_end - trading_start}" if bah.verbose?
      bah.run(trading_start, trading_end, trading_period_in_seconds)
      bah_strategies[trading_period_in_seconds.to_i] ||= []
      bah_strategies[trading_period_in_seconds.to_i] << a.value(trading_end.to_timestamp.to_i) / initial_deposit
    end
  end
  
  percentiles = 0.upto(100).map() {|i| i/100.0}.to_a
  pp bah_strategies.map { |k,v| "#{k}: #{v.percentiles(percentiles)}" }
end