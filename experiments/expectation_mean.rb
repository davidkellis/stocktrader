$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'simulator'

class ExpectationMeanStrategy < Strategy
  attr_reader :exit_timestamp
  
  Modes = [:long, :short]
  
  def initialize(account, tickers_to_trade, small_gain, large_gain, small_loss, large_loss)
    super(account, tickers_to_trade)
    
    @small_gain = small_gain
    @large_gain = large_gain
    @small_loss = small_loss
    @large_loss = large_loss
    
    reset
  end
  
  def trade(ticker, timestamp)
    if @state == 0
      enter_position(ticker, timestamp)
      @state = 1
    elsif @state == 1
      gain = current_gain(ticker, timestamp)
      #puts "state 1: current_gain(#{ticker}, #{timestamp}) = #{gain}"
      if gain >= @small_gain
        exit_position(ticker, timestamp)
      elsif gain <= @large_loss
        exit_position(ticker, timestamp)
      elsif gain <= @small_loss
        @state = 2
      end
    elsif @state == 2
      gain = current_gain(ticker, timestamp)
      #puts "state 2: current_gain(#{ticker}, #{timestamp}) = #{gain}"
      if gain >= @large_gain
        exit_position(ticker, timestamp)
      elsif gain <= @large_loss
        exit_position(ticker, timestamp)
      end
    end
  end
  
  def enter_position(ticker, timestamp)
    case @mode
    when :long
      s = account.buy_amap(ticker, timestamp, amount_per_company)
      #print "bought "
    when :short
      s = account.sell_short_amt(ticker, timestamp, amount_per_company)
      #print "shorted "
    end
    
    @origin_timestamp = timestamp
    @origin_price = account.broker.exchange.quote(ticker, timestamp)
    @origin_shares = s
    #puts "#{s} shares of #{ticker} on #{timestamp} for $#{@origin_price * s + account.broker.buy_commission}"
  end
  
  def exit_position(ticker, timestamp)
    case @mode
    when :long
      s = account.sell_all(ticker, timestamp)
      #print "sold "
    when :short
      s = account.buy(ticker, @origin_shares, timestamp, true)    # buy [potentially] on margin
      #print "bought (potentially on margin) "
    end
    
    @exit_timestamp = timestamp
    #puts "#{s} shares of #{ticker} on #{timestamp} for $#{account.broker.exchange.quote(ticker, timestamp) * s + account.broker.buy_commission}"
    
    throw :abort_strategy
  end
  
  def current_gain(ticker, timestamp)
    price = account.broker.exchange.quote(ticker, timestamp)
    case @mode
    when :long
      (price / @origin_price.to_f) - 1
    when :short
      (@origin_price.to_f / price) - 1
    end
  end
  
  def reset
    account.reset
    @state = 0
    @mode = Modes.rand
    #puts "mode: #{@mode}"
    @origin_price = 0
  end
  
  def to_s
    "ExpectationMeanStrategy:\n" +
    "  Small Gain/Loss #{@small_gain}/#{@small_loss}\n" +
    "  Large Gain/Loss #{@large_gain}/#{@large_loss}\n" +
    "  Mode: #{@mode.to_s}\n" + 
    "  Tickers: #{tickers_to_trade.join(', ')}\n" +
    "  Account: #{account.to_s}"
  end
  
  def parameter_set
    "ExpectationMeanStrategy: Small Gain/Loss #{@small_gain}/#{@small_loss} ; Large Gain/Loss #{@large_gain}/#{@large_loss} ; Mode: #{@mode.to_s}"
  end
end

# this function assumes that the CSV files given to it cover a sufficient period of time
def scalable_randomized_expectation_mean
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  max_trading_period = 1.year    # 3650.days = 2 days short of 10 years
  first_and_last_lines = ->(filename) { [File.new(filename).gets, File::ReadBackwards.new(filename).gets] }
  get_timestamp = ->(line) { Time.from_timestamp(line.strip.split(',').values_at(0..1).join('')) }
  time_between_first_and_last = ->(ticker) { times = first_and_last_lines.("#{ticker}.csv").map(&get_timestamp) ; times.last - times.first }
  tickers = tickers.select { |t|  time_between_first_and_last.(t) >= max_trading_period }
  #pp tickers, tickers.length
  
  commission_fees = 7.00
  initial_deposit = 10000
  trial_count = 1
  
  small_gain = 0.05
  large_gain = 0.1
  small_loss = -0.05
  large_loss = -0.1
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  a = scottrade.new_account(initial_deposit)
  strategy_results = Hash.new
  
  timestamp_specificity = 1.second
  timestamp_increment = 1.minute
  
  # ensure that timestamp_increment >= timestamp_specificity
  timestamp_increment = timestamp_increment < timestamp_specificity ? timestamp_specificity : timestamp_increment
  
  trading_intervals = [1.year]
  
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
      
      # Compute value of portfolio using Expectation Mean strategy
      a.reset
      strategy = ExpectationMeanStrategy.new(a, [symbol], small_gain, large_gain, small_loss, large_loss)
      strategy.run(trading_start, trading_end, timestamp_increment)
      strategy_results[trading_period_in_seconds.to_i] ||= []
      strategy_results[trading_period_in_seconds.to_i] << a.value(strategy.exit_timestamp || trading_end.to_timestamp.to_i) - initial_deposit
    end
  end
  
  puts "Finished trials in #{(Time.now - experiment_start_time).in_minutes} minutes."
  
  pp strategy_results.map { |k,v| "#{k}: #{v.reduce(:+).to_f/v.length}" }
end