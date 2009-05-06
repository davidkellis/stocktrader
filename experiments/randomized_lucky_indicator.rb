$:.unshift File.join(File.dirname(__FILE__), '..', 'lib', 'strategies')

require 'lucky_indicator'

# this function assumes that the CSV files given to it cover a sufficient period of time
def scalable_randomized_lucky_indicator(lucky_percentiles_csv_file)
  puts lucky_percentiles_csv_file
  
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  #pp tickers if $DEBUG
  
  max_trading_period = 1.year
  first_and_last_lines = ->(filename) { [File.new(filename).gets, File::ReadBackwards.new(filename).gets] }
  get_timestamp = ->(line) { Time.from_timestamp(line.strip.split(',').values_at(0..1).join('')) }
  time_between_first_and_last = ->(ticker) { times = first_and_last_lines.("#{ticker}.csv").map(&get_timestamp) ; times.last - times.first }
  tickers = tickers.select { |t|  time_between_first_and_last.(t) >= max_trading_period }
  #pp tickers
  #return
  
  commission_fees = 7.00
  initial_deposit = 100000
  trial_count = 5000            # 10000         5000
  lucky_percentile = 90         # 90            80
  percentage_hold_time = 0.25   # 0.25          0.10
  hold_time_exp = 1             # 1             1
  percentage_price_drop = 0.10  # 0.10          0.10
  lucky_percentiles_csv_table = CSVNumericTable.new(lucky_percentiles_csv_file)
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  lucky_strategies = Hash.new
  
  timestamp_specificity = 1.second
  timestamp_increment = 1.minute
  
  # ensure that timestamp_increment >= timestamp_specificity
  timestamp_increment = timestamp_increment < timestamp_specificity ? timestamp_specificity : timestamp_increment
  
  trading_intervals = [1.week]
  
  experiment_start_time = Time.now
  
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
      strategy = LuckyIndicator.new(a, [symbol], lucky_percentiles_csv_table, lucky_percentile, percentage_hold_time, hold_time_exp, percentage_price_drop)
      #strategy.verbose = true
      #puts "start: #{trading_start} ; end: #{trading_end}, increment: #{trading_period_in_seconds} == #{trading_end - trading_start}" if strategy.verbose?
      strategy.run(trading_start, trading_end, timestamp_increment)
      lucky_strategies[trading_period_in_seconds.to_i] ||= []
      lucky_strategies[trading_period_in_seconds.to_i] << a.value(trading_end.to_timestamp.to_i) / initial_deposit
    end
  end
  
  puts "Finished trials in #{(Time.now - experiment_start_time).in_minutes} minutes."
  
  percentiles = 0.upto(100).map() {|i| i/100.0}.to_a
  pp lucky_strategies.map { |k,v| "#{k}: #{v.percentiles(percentiles)}" }
end