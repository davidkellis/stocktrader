require 'stats'
require 'pp'
require 'activesupport'
require 'extrb'

class Bar
  attr_accessor :date, :time, :id, :open, :high, :low, :close
  
  def initialize(date=0, time=0, id=0, open=0, high=0, low=0, close=0)
    self.date = date
    self.time = time
    self.id = id
    self.open = open.to_f
    self.high = high.to_f
    self.low = low.to_f
    self.close = close.to_f
  end
  
  def to_s
    "#{self.date} @ #{self.time} - #{self.close}"
  end
end

class PriceHistory
  attr_accessor :history
  
  def initialize(filename)
    @history = Array.new
    lines = File.readlines(filename)
    lines.each do |line|
      # record format: Date,Time,Open,High,Low,Close
      @history << Bar.new(*line.strip.split(',').values_at(3..9))
    end
  end
  
  def [](i)
    history[i]
  end
end

class Exchange
  attr_accessor :price_histories
  
  def initialize(*tickers)
    @price_histories = Hash.new
    tickers.each do |t|
      @price_histories[t] = PriceHistory.new("#{t}.csv")
    end
  end
  
  def add_price_history(*tickers)
    tickers.each do |t|
      @price_histories[t] = PriceHistory.new("#{t}.csv")
    end
  end
  
  def remove_price_history(*tickers)
    tickers.each do |t|
      @price_histories[t] = nil
    end
  end
  
  def bar(ticker, bar_index)
    price_histories[ticker][bar_index] || Bar.new     # Note: the OR expression is a fix for when there is not enough data
  end
  
  def quote(ticker, bar_index)
    bar(ticker, bar_index).close
  end
end

class Broker
  attr_reader :buy_commission, :sell_commission, :exchange
  
  def initialize(exchange, buy_commission, sell_commission = buy_commission)
    @buy_commission = buy_commission
    @sell_commission = sell_commission
    @exchange = exchange
  end
  
  def new_account(cash)
    Account.new(self, cash)
  end
  
  # buy as much as possible [with the given amount]
  def buy_amap(account, ticker, bar_index, amount = nil)
    amount ||= account.cash
    amount = [amount, account.cash].min
    max_shares = ((amount - buy_commission) / exchange.quote(ticker, bar_index)).floor
    if max_shares > 0
      buy(account, ticker, max_shares, bar_index)
    else
      0
    end
  end
  
  # buy a number of shares or none at all
  def buy(account, ticker, shares, bar_index)
    cost = exchange.quote(ticker, bar_index) * shares
    if cost >= 0 && account.cash >= cost + buy_commission
      account.cash -= (cost + buy_commission)
      account.portfolio[ticker] += shares
      account.commission_paid += buy_commission
      shares    # return the number of shares bought
    else
      0         # return that 0 shares were bought
    end
  end
  
  def sell_all(account, ticker, bar_index)
    sell(account, ticker, account.portfolio[ticker], bar_index)
  end
  
  # sell a number of shares, up to the number in the portfolio
  def sell(account, ticker, shares, bar_index)
    shares = [shares, account.portfolio[ticker]].min
    gross_profit = exchange.quote(ticker, bar_index) * shares
    post_sale_cash_balance = account.cash + gross_profit
    if(gross_profit >= 0 && post_sale_cash_balance >= sell_commission && account.portfolio[ticker] > 0 && shares > 0)
      account.cash = post_sale_cash_balance - sell_commission
      account.portfolio[ticker] -= shares
      account.commission_paid += sell_commission
      shares
    else
      0         # return that 0 shares were sold
    end
  end
  
  # buy a number of shares, potentially on margin
  def buy_margin(account, ticker, shares, bar_index)
    cost = exchange.quote(ticker, bar_index) * shares
    if cost >= 0
      account.cash -= (cost + buy_commission)
      account.portfolio[ticker] += shares
      account.commission_paid += buy_commission
      shares    # return the number of shares bought
    else
      0         # return that 0 shares were bought
    end
  end
  
  def sell_short(account, ticker, shares, bar_index)
    gross_profit = exchange.quote(ticker, bar_index) * shares
    post_sale_cash_balance = account.cash + gross_profit
    if(gross_profit >= 0 && post_sale_cash_balance >= sell_commission && shares > 0)
      account.cash = post_sale_cash_balance - sell_commission
      account.portfolio[ticker] -= shares
      account.commission_paid += sell_commission
      shares
    else
      0         # return that 0 shares were sold
    end
  end
  
  def sell_short_amt(account, ticker, bar_index, amount = nil)
    amount ||= account.cash > 0 ? account.cash : 0
    max_shares = ((amount - sell_commission) / exchange.quote(ticker, bar_index)).floor
    if max_shares > 0
      sell_short(account, ticker, max_shares, bar_index)
    else
      0
    end
  end
end

class Account
  attr_accessor :portfolio
  attr_accessor :cash
  attr_accessor :broker
  attr_accessor :commission_paid

  def initialize(broker, cash)
    @broker = broker
    @cash = cash.to_f
    @initial_cash = @cash
    @portfolio = Hash.new(0)
    @commission_paid = 0
  end

  def reset
    @cash = @initial_cash
    @portfolio = Hash.new(0)
    @commission_paid = 0
  end

  # buy as much as possible [with the given amount]
  def buy_amap(ticker, bar_index, amount = nil)
    broker.buy_amap(self, ticker, bar_index, amount)
  end
  
  # buy a number of shares or none at all
  def buy(ticker, shares, bar_index)
    broker.buy(self, ticker, shares, bar_index)
  end
  
  # sell all shares held of a stock - completely liquidate the holdings of a particular ticker symbol
  def sell_all(ticker, bar_index)
    broker.sell_all(self, ticker, bar_index)
  end

  # sell a number of shares, up to the number in the portfolio
  def sell(ticker, shares, bar_index)
    broker.sell(self, ticker, shares, bar_index)
  end
  
  def buy_margin(ticker, shares, bar_index)
    broker.buy_margin(self, ticker, shares, bar_index)
  end
  
  def sell_short(ticker, shares, bar_index)
    broker.sell_short(self, ticker, shares, bar_index)
  end
  
  def sell_short_amt(ticker, bar_index, amount = nil)
    broker.sell_short_amt(self, ticker, bar_index, amount)
  end

  def value(bar)
    stock_value = 0
    portfolio.each_pair do |ticker, shares|
      stock_value += broker.exchange.quote(ticker, bar) * shares
    end
    cash + stock_value
  end
  
  def to_s(bar)
    "cash: #{cash}\n" +
      "commission_paid: #{commission_paid}\n" +
      "portfolio holdings as of bar #{bar}: #{portfolio.inspect}\n" +
      "value: #{value(bar)}"
  end
end

class Strategy
  attr_reader :account
  attr_reader :tickers_to_trade
  attr_reader :amount_per_company
  
  def initialize(account, tickers_to_trade)
    @account = account
    @tickers_to_trade = tickers_to_trade
    @amount_per_company = @account.cash / @tickers_to_trade.length
  end
  
  # start_bar is a larger number than end_bar
  def run(start_bar, end_bar, bar_increment = 1)
    bar = start_bar
    
    catch :abort_simulation do
      while(bar <= end_bar)
        #recompute the amount we can invest in each company during this round of investing
        @amount_per_company = account.cash / tickers_to_trade.length
      
        for ticker in tickers_to_trade
          trade(ticker, bar)
        end
      
        bar += bar_increment    # move one bar ahead
      end
    end
  end
end

class ExpectationMeanStrategy < Strategy
  Modes = [:long, :short]
  
  def initialize(account, tickers_to_trade, small_gain, large_gain, small_loss, large_loss)
    super(account, tickers_to_trade)
    
    @small_gain = small_gain
    @large_gain = large_gain
    @small_loss = small_loss
    @large_loss = large_loss
    
    reset
  end
  
  def trade(ticker, bar)
    if @state == 0
      case @mode
      when :long
        s = account.buy_amap(ticker, bar, amount_per_company)
      when :short
        s = account.sell_short_amt(ticker, bar, amount_per_company)
      end
      @origin_price = account.broker.exchange.quote(ticker, bar)
      state += 1
    elsif state == 1
      gain = current_gain(ticker, bar)
      if gain >= @small_gain
        liquidate_position(ticker, bar)
      elsif gain <= @large_loss
        liquidate_position(ticker, bar)
      elsif gain <= @small_loss
        @state = 2
      end
    elsif state == 2
      gain = current_gain(ticker, bar)
      if gain >= @large_gain
        liquidate_position(ticker, bar)
      elsif gain <= @large_loss
        liquidate_position(ticker, bar)
      end
    end
  end
  
  def liquidate_position(ticker, bar, shares_short = 0)
    case @mode
    when :long
      s = account.sell_all(ticker, bar)
    when :short
      s = account.buy_margin(ticker, shares_short, bar)
    end
    
    throw :abort_simulation
  end
  
  def current_gain(ticker, bar)
    case @mode
    when :long
      (account.broker.exchange.quote(ticker, bar) / @origin_price.to_f) - 1
    when :short
      (@origin_price.to_f / account.broker.exchange.quote(ticker, bar)) - 1
    end
  end
  
  def reset
    account.reset
    @state = 0
    @mode = Modes.rand
    @origin_price = 0
  end
  
  def to_s
    "ExpectationMeanStrategy:\n" +
    "  Small Gain/Loss #{@small_gain}/#{@small_loss}\n" +
    "  Large Gain/Loss #{@large_gain}/#{@large_loss}\n" +
    "  Tickers: #{tickers_to_trade.join(', ')}\n" +
    "  Account: #{account.to_s}"
  end
  
  def parameter_set
    "ExpectationMeanStrategy: Small Gain/Loss #{@small_gain}/#{@small_loss} ; Large Gain/Loss #{@large_gain}/#{@large_loss}"
  end
end

class BuyAndHoldStrategy < Strategy
  def initialize(account, tickers_to_trade, last_bar_to_hold)
    super(account, tickers_to_trade)
    
    @last_bar_to_hold = last_bar_to_hold
  end

  def trade(ticker, bar)
    if(account.cash > 0)
      s = account.buy_amap(ticker, bar, amount_per_company)
      if $DEBUG
        b = account.broker.exchange.bar(ticker, bar)
        puts "bought #{s} shares of #{ticker} on #{b.date} at #{b.time}"
      end
    end
    if(bar == @last_bar_to_hold)
      s = account.sell_all(ticker, bar)
      if $DEBUG
        b = account.broker.exchange.bar(ticker, bar)
        puts "sold #{s} shares of #{ticker} on #{b.date} at #{b.time}"
      end
    end
  end

  def to_s
    "Buy-And-Hold:\n" +
    "  Last Bar to Hold: #{@last_bar_to_hold}\n" +
    "  Tickers: #{tickers_to_trade.join(', ')}\n" +
    "  Account: #{account.to_s}"
  end
  
  def parameter_set
    "Buy-and-Hold: last bar to hold: #{@last_bar_to_hold}"
  end
end

class RushtonStrategy < Strategy
  def initialize(account, tickers_to_trade, fn_t, fn_alpha, gamma, min_cooldown)
    super(account, tickers_to_trade)
    
    # fn_t is a function of the duration (time interval) that a stock is held. It returns a "return multiplier" that represents a
    #   "demand" for greater return for longer hold-time durations.
    @fn_t = fn_t
    
    # fn_alpha is a function of the "return multiplier", the return value of fn_t. It returns a percentage gain multiplier that 
    #   represents a precise percentage gain that a stock must yield before it will be sold.
    @fn_alpha = fn_alpha
    
    # gamma is a cool-down multiplier. Let the momentum subside (cool-down) and re-enter only after that amount of cool-down time has elapsed.
    @gamma = gamma
    
    # min_cooldown is the minimum cool-down period that we must wait before re-purchasing a given stock
    @min_cooldown = min_cooldown
    
    # @last_purchase indicates the bar index and price at which a given stock was last purchased, nil if the given stock hasn't ever been owned.
    @last_purchase = Hash.new(Hash.new)
  end
  
=begin
  Enter initially at time 0.

  Once you've entered, let BT be the time at which you bought and
  P the price at which you bought.

  If at any point between BT+t(i) and BT+t(i+1) you have a gain of
  alpha(i), that is the thading price is above (1+alpha(i))*P, sell and
  set your holding time HT = t(i).

  Once you have sold, wait for a time equal to gamma * HT
  OR Price < P to reenter.

  Repeat until time of the experiment expires.


  4:47 PM me: In your trading rule, you said let i = 1, ..., 7. Why does that stop at 7?
  4:49 PM Nelson: if t1 is 15 minutes, then t7 is in decades
    if each time is 3x or 4x as long as the previous
  4:50 PM me: Ok, so each subsequent t value represents an exponentially longer time interval. Does the same apply to alpha(i)?
   Nelson: alpha(i) are increasing
    but not necessarily exponential
=end
  def trade(ticker, bar)
    # this bar's price
    price = account.broker.exchange.quote(ticker, bar)

    # try to buy the given ticker if we aren't holding any shares
    if account.portfolio[ticker] == 0    # we have zero holdings of the given ticker
      last_hold_time = if @last_purchase[ticker][:buy_bar] && @last_purchase[ticker][:sell_bar]
                         @last_purchase[ticker][:buy_bar] - @last_purchase[ticker][:sell_bar]     # compute the last hold-time
                       else
                         0
                       end
      
      # Wait for a time interval equal to gamma * HT to pass (cool-down period) OR Price < P to buy more:
      #   if we have never purchased the given stock/ticker,
      #   OR the current price is less than the price at which we last purchased this stock,
      #   OR (the time elapsed since our last sell-date is greater than or equal to the minimum cool-down duration
      #       AND the time elapsed since our last sell-date is greater than or equal to gamma * the last hold-time duration)
      if(!@last_purchase.key?(ticker) || 
         price < @last_purchase[ticker][:price] || 
         ((t = (@last_purchase[ticker][:sell_bar] - bar)) >= @min_cooldown && 
          t >= @gamma * last_hold_time))
          
        s = account.buy_amap(ticker, bar, amount_per_company)
        @last_purchase[ticker] = {price: price, buy_bar: bar}
        puts "bought #{s} shares of #{ticker} on #{account.broker.exchange.bar(ticker, bar).date}" if $DEBUG
      end
    else                                  # try to sell our holdings of the given ticker
      # compute t, the return multiplier, given the interval between now and last purchase of the given stock (ticker)
      t = @fn_t.call(@last_purchase[ticker][:buy_bar] - bar)

      # compute alpha, given the value t, to determine the percentage gain multiplier
      alpha = @fn_alpha.call(t)

      puts "t = #{t}", "alpha = #{alpha}" if $DEBUG

      puts "price of #{ticker} on #{account.broker.exchange.bar(ticker, bar).date} is #{price}" if $DEBUG
      
      # if trading price is above (1+alpha(i))*P, sell
      if(price > (1.0 + alpha) * @last_purchase[ticker][:price])
        s = account.sell_all(ticker, bar)
        @last_purchase[ticker][:sell_bar] = bar
        puts "sold #{s} shares of #{ticker} on #{account.broker.exchange.bar(ticker, bar).date}" if $DEBUG
      end
    end
    
    puts "account: #{account.to_s(bar)}" if $DEBUG
  end
  
  def to_s
    "JNR:\n" +
    "  T: #{@fn_t}\n" +
    "  Alpha: #{@fn_alpha}\n" +
    "  Gamma: #{@gamma}\n" +
    "  Tickers: #{tickers_to_trade.join(', ')}\n" +
    "  Account: #{account.to_s}"
  end

  def parameter_set
    "JNR: " +
    "  T: #{@fn_t} " +
    "  Alpha: #{@fn_alpha} " +
    "  Gamma: #{@gamma}"
  end
end

def performance
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  sample_size = 10
  portfolio_size = 1
  commission_fees = 7.00
  initial_deposit = 100000
  max_averaging_period = 200
  max_n_period = 200
  trading_period_in_bars = 365*2
  number_of_best_strategies_per_portfolio = 3
  
  # randomize the order of the ticker symbols
  #srand(1234)
  tickers.shuffle!
  
  # this creates a sample of ticker sets (which have been randomized)
  ticker_sets = tickers.each_slice(portfolio_size).to_a.slice(0...sample_size)
  
  puts "Portfolios of stocks:"
  p ticker_sets
  puts
  
  e = Exchange.new()
  scottrade = Broker.new(e, commission_fees)
  best_strategies = Hash.new
  
  fn_t = ->(duration) do
    Math.log(duration, 2)
  end
  
  fn_alpha = ->(t_value) do
    t_value / 100.0
  end
  
  ticker_sets.each do |ticker_set|
    # NOTE: A ticker_set is a portfolio of stocks that are treated as an independent unit

    # load the exchange up with price history just-in-time style
    e.add_price_history(*ticker_set)

    all_strategies = Hash.new

    # Test JNR Strategy
    gamma = 1.0
    min_cooldown = 1
    # Compute value of portfolio using JNR strategy
    a = scottrade.new_account(initial_deposit)
    jnr = RushtonStrategy.new(a, ticker_set, fn_t, fn_alpha, gamma, min_cooldown)
    jnr.run(trading_period_in_bars)
    all_strategies[jnr] = a.value(0)
    #puts "Averaging Period: #{avg_period}",a.to_s(1),'***************************************************************'


    # Compute value of portfolio using Buy-And-Hold strategy
    # Buy as soon as possible (365 bars ago -> trading_period_in_bars) and sell when the simulation bar becomes yesterbar (1 bar ago)
    a = scottrade.new_account(initial_deposit)
    bah = BuyAndHoldStrategy.new(a, ticker_set, 0)
    bah.run(trading_period_in_bars)
    all_strategies[bah] = a.value(0)
    #puts "Buy-And-Hold: ",a.to_s(1),'***************************************************************'

    # Sort the strategies by overall performance and output the best 5
    sorted_strategies = all_strategies.sort {|a,b| b[1] <=> a[1] }  # a,b[0] -> key ; a,b[1] -> stored value
    # sorted_strategies is an Array of pairs (i.e. each pair is an array with two elements)
    # sorted_strategies[0...10].each { |pair| puts pair[0],'*******************' }

    #best_strategies_per_portfolio[ticker_set.join(',')] = sorted_strategies[0...number_of_best_strategies_per_portfolio]

    best_strategies = sorted_strategies[0...number_of_best_strategies_per_portfolio]
    puts "portfolio: #{ticker_set.join(',')}"
    puts "best strategies:"
    for strategy_value_pair in best_strategies
      puts "value: #{strategy_value_pair[1]}",strategy_value_pair[0],"-----"
    end
    puts "\n"
    
    # remove the price history for the ticker_set from the exchange price history
    e.remove_price_history(*ticker_set)
  end
  
  
=begin
  best_strategies_per_portfolio.each do |ticker_set,best_strategies|
    puts "portfolio: #{ticker_set}"
    puts "best strategies:"
    for strategy_value_pair in best_strategies
      puts "value: #{strategy_value_pair[1]}",strategy_value_pair[0],"-----"
    end
    puts "\n"
  end
=end
end

def randomized_buy_and_hold
  tickers = ARGV.map {|t| t.upcase.chomp('.CSV') }
  
  commission_fees = 7.00
  initial_deposit = 100000
  trial_count = 1000000
  
  e = Exchange.new()
  e.add_price_history(*tickers)               #pre-load all applicable price-histories
  scottrade = Broker.new(e, commission_fees)
  bah_strategies = Hash.new
  
  bar_specificity = 1.second
  bar_increment = 5.seconds
  
  trading_intervals = [1.minute, 5.minutes, 10.minutes, 30.minutes].map { |t| t.to_bars(bar_specificity).to_i }
  
  trading_intervals.each do |trading_period_in_bars|
    trial_count.times do
      # pick a random ticker symbol and trading origin
      symbol = tickers.rand
      trading_origin = e.price_histories[symbol].history.random_index     #assumes the price history for symbol has been pre-loaded
      if(trading_origin + 1 < trading_period_in_bars)
        l = e.price_histories[symbol].history.length
        trading_origin = trading_period_in_bars >= l ? l - 1 : trading_period_in_bars
      end
      last_bar_of_trading = trading_origin - trading_period_in_bars + 1

      # Compute value of portfolio using Buy-And-Hold strategy
      a = scottrade.new_account(initial_deposit)
      bah = BuyAndHoldStrategy.new(a, [symbol], 0)
      puts "start: #{trading_origin} ; end: #{last_bar_of_trading}, increment: #{trading_period_in_bars - 1}" if $DEBUG
      bah.run(trading_origin, last_bar_of_trading, trading_origin - last_bar_of_trading)      # bar_increment.to_bars(bar_specificity)
      bah_strategies[trading_period_in_bars.to_i] ||= []
      bah_strategies[trading_period_in_bars.to_i] << a.value(last_bar_of_trading) / initial_deposit
    end
  end
  
  percentiles = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
  pp bah_strategies.map { |k,v| "#{k}: #{v.percentiles(percentiles)}" }
end


$DEBUG = true

#performance
randomized_buy_and_hold